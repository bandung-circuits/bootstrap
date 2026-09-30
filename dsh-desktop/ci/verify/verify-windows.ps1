# dsh-desktop/ci/verify/verify-windows.ps1 -- run INSIDE the Windows VM AFTER the
# DeepSeek Harness app has been installed and dsh-desktop/prep.ps1 has run.
# Asserts: workspace seeds, in-workspace venv with crawl4ai, the crawl4ai patch
# pointing at the workspace venv (with in-workspace browsers/data env), and that
# the app's bundled harness composes the patch (dump-config).
$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0; $skip = 0
function OK($m){ Write-Host "  PASS  $m"; $script:pass++ }
function NO($m){ Write-Host "  FAIL  $m"; $script:fail++ }
function SK($m){ Write-Host "  SKIP  $m"; $script:skip++ }

$WS      = Join-Path $env:USERPROFILE 'ai-workspace'
# Official DeepSeek Harness data root + desktop profile (mirrors prep.ps1).
$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$HARNESS = Join-Path $DshHome 'profiles\desktop'
$patch   = Join-Path $HARNESS 'cordis.patch.yml'
$venvPy  = Join-Path $WS '.venv\Scripts\python.exe'
$cr4exe  = Join-Path $WS '.venv\Scripts\crawl4ai-search.exe'

# --- seeds ---
foreach ($f in 'AGENTS.md','README.md','.gitignore','NEXT-STEPS.md') {
    if (Test-Path (Join-Path $WS $f)) { OK "$f seeded" } else { NO "$f seeded" }
}

# --- in-workspace python + crawl4ai ---
$importOk = $false
if (Test-Path $venvPy) {
    & $venvPy -c 'import crawl4ai_mcp_server' 2>$null | Out-Null
    $importOk = ($LASTEXITCODE -eq 0)
}
if ($importOk) {
    OK 'venv python imports crawl4ai_mcp_server (in-workspace)'
} else {
    NO 'workspace venv missing or crawl4ai_mcp_server not importable'
}
if (Test-Path $cr4exe) { OK "crawl4ai executable present ($cr4exe)" } else { NO 'crawl4ai executable missing' }

# sitecustomize.py must redirect crawl4ai data/browser into the workspace for
# ANY venv python invocation.
$sc = Join-Path $WS '.venv\Lib\site-packages\sitecustomize.py'
if ((Test-Path $sc) -and ((Get-Content $sc -Raw) -match 'CRAWL4_AI_BASE_DIRECTORY') -and ((Get-Content $sc -Raw) -match 'PLAYWRIGHT_BROWSERS_PATH')) {
    OK 'venv sitecustomize redirects crawl4ai data/browser to workspace'
} else { NO 'venv sitecustomize missing or lacks workspace env' }

# default permission preset pinned to danger-full-access (Full Access)
$settings = Join-Path $HARNESS 'settings.yaml'
if ((Test-Path $settings) -and ((Get-Content $settings -Raw) -match 'defaultPreset:\s*danger-full-access')) {
    OK 'harness settings.yaml pins permission default to danger-full-access'
} else { NO 'harness settings.yaml does not pin danger-full-access' }

# --- git (system, or the workspace portable MinGit) ---
$gitOk = $false
$sysGit = Get-Command git.exe -ErrorAction SilentlyContinue
if ($sysGit) { OK "git present (system: $(git.exe --version))"; $gitOk = $true }
$localGit = Join-Path $WS '.mingit\cmd\git.exe'
if ((-not $gitOk) -and (Test-Path $localGit)) { OK "git present (workspace portable: $(& $localGit --version))"; $gitOk = $true }
if (-not $gitOk) { NO 'git missing (no system git and no workspace portable git)' }

# --- patch ---
$pc = Get-Content $patch -Raw -ErrorAction SilentlyContinue
if ($pc -match 'mcp-crawl4ai' -and $pc -match '@deepseek-ai/dsh-mcp-client' -and $pc -match [regex]::Escape("command: $cr4exe") -and $pc -match 'CRAWL4_AI_BASE_DIRECTORY' -and $pc -match 'PLAYWRIGHT_BROWSERS_PATH' -and $pc -match 'PYTHONUTF8') {
    OK 'patch: official mcp-client -> workspace venv + in-workspace browsers/data + PYTHONUTF8'
} else {
    NO 'patch shape wrong -- see below'
    Write-Host ($pc.Substring(0,[Math]::Min(400,[string]$pc.Length)))
}

# --- bundled harness composes the patch; plugins land on FIRST OPEN ---
# The official desktop refuses the CLI on its `desktop` profile: `dsh web
# --dump-config` errors "profile ... managed exclusively by the Electron
# application", and plugin install needs the app opened once to initialize the
# profile. So macOS/Windows CI can't dump the composed toolset from outside the
# app — that happens at app runtime. What we CAN assert: the desktop profile
# dir exists with the patch (tier-1 already checks the patch file) and, once
# initialized, that the plugin manager can list the profile's plugins.
$profileInit = Test-Path (Join-Path $HARNESS 'package.json')
$appDir = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'),
  (Join-Path $env:ProgramFiles 'DeepSeek Harness')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
$cli = $null
if ($appDir) {
    $cli = Get-ChildItem (Join-Path $appDir 'resources\runtime\cli\bin') -Filter 'dsh*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '' -or $_.Extension -in '.cmd','.ps1' } | Select-Object -First 1
}
if ($profileInit -and $cli) {
    $env:DSH_HOME = $DshHome
    $list = & $cli.FullName plugin --profile desktop list *>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        OK 'official plugin manager can operate the desktop profile (app-exclusive runtime OK)'
    } else {
        NO "plugin manager could not list the desktop profile — profile may be broken: $list"
    }
} elseif ($appDir -and -not $profileInit) {
    SK 'desktop profile not initialized yet (open app once, then re-run setup) — plugin/compose deferred'
} else {
    NO "bundled official harness not found (app=$appDir)"
}

# --- default plugins installed by prep (dshmarket + dsh-better-reasoning-effort) ---
$pkgJson = Join-Path $HARNESS 'package.json'
if (Test-Path $pkgJson) {
  try { $pj = Get-Content $pkgJson -Raw | ConvertFrom-Json } catch { $pj = $null }
  if ($pj) {
    $deps = $pj.dependencies.PSObject.Properties.Name
    $bundles = $pj.dsh.profile.bundles
    if ($deps -contains 'dshmarket' -and $bundles -contains 'dshmarket') { OK 'plugin dshmarket in deps+bundles' } else { NO 'plugin dshmarket missing' }
    if ($deps -contains 'dsh-better-reasoning-effort' -and $bundles -contains 'dsh-better-reasoning-effort') { OK 'plugin dsh-better-reasoning-effort in deps+bundles' } else { NO 'plugin dsh-better-reasoning-effort missing' }
  } else { NO 'profiles/desktop/package.json unreadable' }
} elseif (-not $profileInit) {
  SK 'desktop profile not initialized yet (open app once, then re-run setup) — plugins deferred by design'
} else { NO 'profiles/desktop/package.json not found (plugins not installed)' }

Write-Host ''
Write-Host "RESULT: $pass passed, $fail failed, $skip skipped"
exit $fail