# dsh-desktop/prep.ps1 -- one-command workspace prep for DeepSeek Harness (Windows).
#
# deployed:  (stamped by ci/deploy-pages.yml)
#
# Usage (PowerShell):
#   iex (curl.exe -sL https://bandung-circuits.github.io/bootstrap/dsh-desktop/prep.ps1 | Out-String)
# or from a clone:
#   .\dsh-desktop\prep.ps1
#
# Prerequisite: the official DeepSeek Harness desktop app installed
# (https://deepseek.com/harness). Platforms: Apple-silicon macOS + Windows x64
# only (the official desktop has no Intel/linux build).
#
# Everything is installed INSIDE the workspace so the app's subprocesses can
# find it without ~\.local\bin (not on PATH) or ~\.crawl4ai:
#   %USERPROFILE%\ai-workspace\
#     AGENTS.md README.md .gitignore NEXT-STEPS.md   seeds
#     .venv\                       python + crawl4ai-search-mcp pre-installed
#     .browsers\                   Playwright Chromium (pre-downloaded)
#     .crawl4ai\                   crawl4ai data
#     .local\bin\                  uv (helper, not needed at runtime)
#
# The crawl4ai MCP server runs the workspace venv's crawl4ai-search.exe by
# absolute path. Our config lives in the desktop profile patch layer
# (%USERPROFILE%\.dsh\profiles\desktop); the model key is entered by the
# learner in the app.

#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$REPO_RAW = 'https://bandung-circuits.github.io/bootstrap/dsh-desktop'
$_TmpTemplates = ''

function Note($m){ Write-Host "==> $m" -ForegroundColor Green }
function Warn($m){ Write-Host "!! $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# ---------- paths (env-overridable for tests; PSCommandPath is $null under iex) ----------
$WS = if ($env:WORKSPACE_DIR) { $env:WORKSPACE_DIR } else { Join-Path $env:USERPROFILE 'ai-workspace' }
# The official desktop shares the dsh-cli data root: $DSH_HOME (default
# ~/.dsh = %USERPROFILE%\.dsh). Electron-owned config lives in the DESKTOP
# PROFILE's own patch layer, $DSH_HOME\profiles\desktop. Setting DSH_HOME
# redirects the whole root (the app honors it via resolveDshHome()).
$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$ProfileName = 'desktop'
$HARNESS = Join-Path $DshHome "profiles\$ProfileName"
$UV      = Join-Path $WS '.local\bin\uv.exe'
$VENV_PY = Join-Path $WS '.venv\Scripts\python.exe'
$BROWSER = Join-Path $WS '.browsers'
$CR4     = Join-Path $WS '.venv\Scripts\crawl4ai-search.exe'

# ---------- templates ----------
function Get-Templates {
    $here = ''
    if ($PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
    if ($here -and (Test-Path (Join-Path $here 'templates\workspace'))) {
        $script:TW = Join-Path $here 'templates\workspace'
        $script:TP = Join-Path $here 'templates\dsh-desktop'
        return
    }
    $_TmpTemplates = Join-Path $env:TEMP ("dshdesktop-tpl-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path (Join-Path $_TmpTemplates 'workspace'), (Join-Path $_TmpTemplates 'dsh-desktop') | Out-Null
    foreach ($f in 'AGENTS.md','README.md','_gitignore','NEXT-STEPS.md') {
        Invoke-WebRequest "$REPO_RAW/templates/workspace/$f" -OutFile (Join-Path $_TmpTemplates "workspace\$f") -TimeoutSec 30
    }
    Invoke-WebRequest "$REPO_RAW/templates/dsh-desktop/crawl4ai-patch.yml" -OutFile (Join-Path $_TmpTemplates 'dsh-desktop\crawl4ai-patch.yml') -TimeoutSec 30
    $script:TW = Join-Path $_TmpTemplates 'workspace'
    $script:TP = Join-Path $_TmpTemplates 'dsh-desktop'
}

# ---------- 1. workspace seeds ----------
function Seed-Workspace {
    New-Item -ItemType Directory -Force -Path $WS | Out-Null
    $map = @('AGENTS.md:AGENTS.md','README.md:README.md','_gitignore:.gitignore','NEXT-STEPS.md:NEXT-STEPS.md')
    foreach ($m in $map) {
        $src = $m.Split(':')[0]; $dst = $m.Split(':')[1]
        $path = Join-Path $WS $dst
        if (Test-Path $path) { Note "kept existing $path"; continue }
        Copy-Item (Join-Path $script:TW $src) $path
        Note "seeded $path"
    }
}

# ---------- 2. uv into the workspace ----------
function Ensure-Uv {
    if (Test-Path $UV) { Note "uv present ($UV)"; return }
    if ($env:PREP_NO_UV -eq '1') { Note 'skipping uv install (PREP_NO_UV=1)'; return }
    Note "Installing uv into $($WS)\.local\bin"
    New-Item -ItemType Directory -Force -Path (Split-Path $UV -Parent) | Out-Null
    $installer = Join-Path $env:TEMP 'astral-uv-install.ps1'
    Invoke-WebRequest 'https://astral.sh/uv/install.ps1' -OutFile $installer -TimeoutSec 60
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $env:UV_INSTALL_DIR = Split-Path $UV -Parent
    $p = Start-Process -FilePath $psExe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$installer`"" -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { Err "uv installer failed (exit $($p.ExitCode))" }
    Remove-Item Env:UV_INSTALL_DIR -ErrorAction SilentlyContinue
    if (-not (Test-Path $UV)) { Err "uv not found at $UV" }
    Note 'uv installed'
}

# ---------- 3. venv + crawl4ai-search-mcp, all inside the workspace ----------
function Ensure-Venv {
    Ensure-Uv
    if (-not (Test-Path $CR4)) {
        Note "Creating venv and installing crawl4ai-search-mcp==0.1.1"
        & $UV venv (Join-Path $WS '.venv')
        & $UV pip install -p (Join-Path $WS '.venv') 'crawl4ai-search-mcp==0.1.1'
    }
    if (-not (Test-Path $CR4)) { Err "crawl4ai-search not found at $CR4" }
    Note 'creating venv + crawl4ai complete'
    # sitecustomize.py: imported at every venv python startup, so ANY venv
    # python (the MCP server AND direct agent runs) directs crawl4ai's data and
    # the Playwright browser into the workspace (else ~\.crawl4ai is used and
    # blocked by the sandbox).
    $pyFind = "import site; ps=[p for p in site.getsitepackages() if p.replace('\\','/').endswith('site-packages')]; print(ps[0] if ps else '')"
    $sp = & $VENV_PY -c $pyFind 2>$null
    if (-not $sp -or -not (Test-Path $sp)) { $sp = Join-Path $WS '.venv\Lib\site-packages' }
    New-Item -ItemType Directory -Force -Path $sp | Out-Null
    $sc = Join-Path $sp 'sitecustomize.py'
    if (-not (Test-Path $sc)) {
        Set-Content -Path $sc -Value @'
import os, sys
# sitecustomize: every venv python startup. sys.prefix is the venv dir
# (~/ai-workspace/.venv); the workspace is its parent (works on macOS
# lib/python3.X/site-packages and Windows Lib/site-packages).
_WS = os.path.dirname(sys.prefix)
os.environ.setdefault('CRAWL4_AI_BASE_DIRECTORY', _WS)
os.environ.setdefault('PLAYWRIGHT_BROWSERS_PATH', os.path.join(_WS, '.browsers'))
'@ -Encoding ASCII -NoNewline
        Note "wrote $sc (crawl4ai data/browser stay in the workspace)"
    } else {
        Note "sitecustomize already present ($sc)"
    }
}

# ---------- 4. pre-download the Playwright Chromium into the workspace ----------
function Ensure-Browser {
    $probe = Get-ChildItem $BROWSER -Recurse -Filter 'chrome.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($probe) { Note "browser already present in $BROWSER"; return }
    if ($env:PREP_NO_BROWSER -eq '1') { Note 'skipping browser pre-download (PREP_NO_BROWSER=1)'; return }
    Note "Pre-downloading the Chromium browser into $BROWSER"
    New-Item -ItemType Directory -Force -Path $BROWSER | Out-Null
    $env:PLAYWRIGHT_BROWSERS_PATH = $BROWSER
    try {
        & $VENV_PY -m playwright install chromium | Out-Null
        Note 'browser ready'
    } catch {
        Warn "browser pre-download failed: $($_.Exception.Message) -- first search will download it automatically"
    }
    Remove-Item Env:PLAYWRIGHT_BROWSERS_PATH -ErrorAction SilentlyContinue
}

# ---------- 5. crawl4ai MCP (official mcp-client), self-contained + self-healing ----------
function Remove-StaleCrawl4aiBlock {
    param([string]$patch)
    $lines = Get-Content $patch
    $out = New-Object System.Collections.ArrayList
    $buf = New-Object System.Collections.ArrayList
    $drop = $false
    foreach ($ln in $lines) {
        if ($ln -match '^\s*- ') {
            # new top-level item: flush previous
            if ($buf.Count -gt 0 -and -not $drop) { foreach ($b in $buf) { [void]$out.Add($b) } }
            $buf = New-Object System.Collections.ArrayList
            $drop = ($ln -match 'mcp-crawl4ai')
            [void]$buf.Add($ln)
        } elseif ($buf.Count -gt 0) {
            [void]$buf.Add($ln)
        } else {
            [void]$out.Add($ln)
        }
    }
    if ($buf.Count -gt 0 -and -not $drop) { foreach ($b in $buf) { [void]$out.Add($b) } }
    Set-Content -Path $patch -Value $out -Encoding UTF8
}

function Ensure-McpCrawl4ai {
    New-Item -ItemType Directory -Force -Path $HARNESS | Out-Null
    if (-not (Test-Path $CR4)) { Err "crawl4ai-search not found at $CR4 -- cannot write a valid MCP row" }
    $patch = Join-Path $HARNESS 'cordis.patch.yml'
    if ((Test-Path $patch) -and (Select-String -Path $patch -SimpleMatch "command: $CR4" -Quiet) -and (Select-String -Path $patch -SimpleMatch 'PYTHONUTF8' -Quiet)) {
        Note "crawl4ai MCP already enabled with the workspace venv in $patch"
        return
    }
    # strip any stale crawl4ai insert block (old ~\.local\bin\uvx path etc.),
    # then write the fresh one -- self-heals after an earlier bad prep.
    if (Test-Path $patch) { Remove-StaleCrawl4aiBlock -patch $patch }
    $block = (Get-Content -Raw (Join-Path $script:TP 'crawl4ai-patch.yml'))
    $block = $block.Replace('{{CRAWL4AI_BIN}}', $CR4).Replace('{{WORKSPACE}}', $WS)
    Add-Content -Path $patch -Value "`n# DeepSeek Harness profile patch layer (desktop profile; applies after every bundle layer)$([char]10)$block" -Encoding UTF8
    Note "enabled crawl4ai MCP in $patch (pins $CR4)"
}

# ---------- 6. default permission preset: Full Access (danger-full-access) ----------
function Ensure-PermissionDefault {
    New-Item -ItemType Directory -Force -Path $HARNESS | Out-Null
    $settings = Join-Path $HARNESS 'settings.yaml'
    if ((Test-Path $settings) -and (Select-String -Path $settings -Pattern '^\s*defaultPreset:' -Quiet)) {
        Note "permission default already set in $settings"
        return
    }
    Note 'Setting default permission preset to danger-full-access'
    if (-not (Test-Path $settings)) {
        Set-Content -Path $settings -Value "permission:`n  defaultPreset: danger-full-access" -Encoding UTF8
    } elseif (Select-String -Path $settings -Pattern '^permission:' -Quiet) {
        $out = New-Object System.Collections.ArrayList
        foreach ($line in Get-Content $settings) {
            [void]$out.Add($line)
            if ($line -match '^permission:') { [void]$out.Add('  defaultPreset: danger-full-access') }
        }
        Set-Content -Path $settings -Value $out -Encoding UTF8
    } else {
        Add-Content -Path $settings -Value "`npermission:`n  defaultPreset: danger-full-access" -Encoding UTF8
    }
    Note 'done'
}

# ---------- 7. git (portable, inside the workspace -- no winget/system install) ----------
# The user-facing command already relies on curl.exe; winget would be a NEW
# assumption (and isn't present on some Windows builds). Instead download the
# MinGit portable zip with curl and extract it into the workspace with the
# tar.exe that ships in Windows 10/11 -- fully self-contained, no UAC, no PATH.
function Ensure-Git {
    $localGit = Join-Path $WS '.mingit\cmd\git.exe'
    if (Get-Command git.exe -ErrorAction SilentlyContinue) { Note "git present (system: $(git.exe --version))"; return }
    if (Test-Path $localGit) { Note "git present (workspace portable: $((& $localGit --version)))"; return }
    if ($env:PREP_NO_GIT -eq '1') { Note 'skipping git (PREP_NO_GIT=1)'; return }
    Note "Downloading portable git (MinGit) into $($WS)\.mingit (curl, no system install)"
    $zipUrl = 'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.5/MinGit-2.55.0.5-64-bit.zip'
    $dst = Join-Path $WS '.mingit'
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    $tmp = Join-Path $env:TEMP 'mingit.zip'
    curl.exe -fsSL $zipUrl -o $tmp
    tar -xf $tmp -C $dst
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    if (Test-Path $localGit) { Note "git installed (workspace portable: $((& $localGit --version)))" }
    else { Warn 'git extraction failed; you can still use the AI without git' }
}

# ---------- 8. default DSH plugins (Plugin Market + reasoning-effort) ----------
# Installs two community plugins into the DSH `desktop` profile (the official
# desktop app's profile) so every learner gets them by default, using the app's
# OWN bundled dsh CLI + pnpm (no system node/pnpm assumed).
# `dsh plugin --profile desktop add <pkg>` initializes the profile on first use,
# adds the package to deps AND dsh.profile.bundles, and pnpm-installs it.
# Idempotent.   dshmarket -> Settings -> Plugin Market.
#   dsh-better-reasoning-effort -> per-model reasoning-effort slider with a
#   built-in model knowledge base (knows each vendor's correct effort levels);
#   auto-fills reasoningEfforts on app launch. Needs DSH kernel >= 0.1.5-alpha.1
#   (the official desktop ships well beyond it); best-effort if absent.
$DefaultPlugins = @('dshmarket', 'dsh-better-reasoning-effort')

function Find-AppDir {
    foreach ($c in @((Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness'), (Join-Path $env:ProgramFiles 'DeepSeek Harness'))) {
        if (Test-Path $c) { return $c }
    }
    return ''
}

function Ensure-Plugins {
    if ($env:PREP_NO_PLUGINS -eq '1') { Note 'skipping plugins (PREP_NO_PLUGINS=1)'; return }
    $appDir = Find-AppDir
    if (-not $appDir) { Warn 'DeepSeek Harness app not found -- skipping plugin install. Install it from https://deepseek.com/harness and re-run.'; return }
    # The official desktop bundles a dsh CLI under resources\runtime\cli\bin.
    $node = Get-ChildItem (Join-Path $appDir 'resources\runtime') -Recurse -Filter 'node.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    $cli  = @(Get-ChildItem (Join-Path $appDir 'resources\runtime\cli\bin') -Filter 'dsh*' -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '' -or $_.Extension -in '.cmd','.ps1' } | Select-Object -First 1) | Select-Object -First 1
    # Fallback to the older in-bundle node + bin.js layout if the unpacked cli is absent.
    if (-not $cli) {
        $legacyNode = Get-ChildItem $appDir -Recurse -Filter 'node.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
        $legacyDsh  = Get-ChildItem $appDir -Recurse -Filter 'bin.js' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\dsh\\' } | Select-Object -First 1
        if ($legacyDsh) { $cli = $legacyDsh; if (-not $node) { $node = $legacyNode } }
    }
    if (-not $cli) { Warn "bundled dsh CLI not found under $appDir -- skipping plugin install"; return }
    # The app's main process should not run while pnpm mutates the profile dir.
    $run = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue
    if ($run) {
        # The app may still be shutting down after the learner quit it; give it
        # a short grace period before skipping, so a quick re-run isn't a no-op.
        for ($i = 0; $i -lt 7 -and (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue); $i++) { Start-Sleep -Seconds 3 }
        if (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue) {
            Warn 'DeepSeek Harness is running -- quit it before plugin install; skipping plugins for now'; return
        }
    }
    # The desktop app must be opened once (first run) to initialize its profile
    # before `dsh plugin --profile desktop` will act. Fresh installs haven't done
    # that yet, so defer plugins with clear guidance; re-running setup after the
    # learner opens+quits the app installs them (idempotent).
    if (-not (Test-Path (Join-Path $HARNESS 'package.json'))) {
        Warn 'The desktop profile is not initialized yet. Open DeepSeek Harness once so it creates its profile, quit it, then re-run this setup command -- it will then install the default plugins. Skipping plugins for now (non-fatal).'
        return
    }
    # `dsh plugin add` shells out to a bare `pnpm`; learners rarely have pnpm on
    # PATH. Point a pnpm.cmd shim at the app's OWN bundled node + pnpm.cjs and
    # put it first on PATH for the call.
    $pnpmCjs = Get-ChildItem (Join-Path $appDir 'resources\runtime\pnpm\bin') -Filter 'pnpm.cjs' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $pnpmCjs) {
        $pnpmCjs = Get-ChildItem $appDir -Recurse -Filter 'pnpm.cjs' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '\\pnpm\\bin\\' } | Select-Object -First 1
    }
    if ($pnpmCjs -and $node) {
        $shimDir = Join-Path $env:TEMP 'dsh-pnpm-shim'
        New-Item -ItemType Directory -Force -Path $shimDir | Out-Null
        Set-Content -Path (Join-Path $shimDir 'pnpm.cmd') -Value "@`"$($node.FullName)`" `"$($pnpmCjs.FullName)`" %*" -Encoding ASCII
        $env:PATH = "$shimDir;$env:PATH"
    }
    $env:DSH_HOME = $DshHome     # root, so `--profile desktop` resolves profiles/desktop
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    foreach ($pkg in $DefaultPlugins) {
        Note "installing DSH plugin $pkg (desktop profile)"
        # sanitize the package name for the log filename -- scoped packages
        # contain a slash, which would turn the Join-Path into a missing
        # subdirectory and silently break the redirect.
        $safe = $pkg -replace '[/\\:]', '-'
        $log = Join-Path $env:TEMP "dsh-prep-plugin-$safe.log"
        $added = $false
        if ($node -and $cli.FullName -match 'bin\.js$') {
            & $node.FullName $cli.FullName plugin --profile $ProfileName add $pkg *>$log
        } else {
            & $cli.FullName plugin --profile $ProfileName add $pkg *>$log
        }
        if ($LASTEXITCODE -eq 0) { $added = $true }
        else {
            # On a newer dsh the app may gate a community plugin over a
            # peer-dependency gap; the CLI prints the exact exemption command.
            # Accept the documented risk it offers (its plugin-manager UI does
            # the same) and retry once. Non-fatal if still refused.
            # NOTE: use Select-String -- `break` inside ForEach-Object aborts
            # the whole pipeline assignment, which silently left $cmd null.
            # The CLI wraps its message at console width, so join lines first
            # or the command (ending in --accept-risk) is split across lines.
            $raw = Get-Content $log -Raw -ErrorAction SilentlyContinue
            $cmd = $null
            if ($raw) {
                $joined = $raw -replace "\r?\n", " "
                if ($joined -match 'allow-version (.+?)--accept-risk') {
                    $cmd = ($Matches[1] -replace '\s+', ' ').Trim()
                }
            }
            if ($cmd) {
                Note "granting compatibility exemption for $pkg ($cmd)"
                $args = @($cmd.Trim() -split '\s+') -ne ''
                if ($node -and $cli.FullName -match 'bin\.js$') { & $node.FullName $cli.FullName plugin --profile $ProfileName @args *>$log }
                else { & $cli.FullName plugin --profile $ProfileName @args *>$log }
                if ($node -and $cli.FullName -match 'bin\.js$') { & $node.FullName $cli.FullName plugin --profile $ProfileName add $pkg *>$log }
                else { & $cli.FullName plugin --profile $ProfileName add $pkg *>$log }
                if ($LASTEXITCODE -eq 0) { $added = $true }
            }
        }
        if ($added) {
            Note "plugin $pkg installed"
        } else {
            Warn "plugin $pkg install failed (exit $LASTEXITCODE) -- non-fatal; the workspace still works"
            Get-Content $log -ErrorAction SilentlyContinue | Select-Object -Last 12 | ForEach-Object { Write-Host "    $_" }
        }
    }
    $ErrorActionPreference = $prevEAP
}

# ---------- main ----------
Get-Templates
Note 'Creating and seeding the AI workspace'
Seed-Workspace
Note 'Installing uv into the workspace'
Ensure-Uv
Note 'Creating the workspace venv with crawl4ai'
Ensure-Venv
Note 'Pre-downloading the Chromium browser'
Ensure-Browser
Note 'Enabling crawl4ai MCP (official DSH mcp-client)'
Ensure-McpCrawl4ai

Note 'Setting the default permission preset'
Ensure-PermissionDefault

Note 'Checking git'
Ensure-Git

Note 'Installing default DSH plugins (Plugin Market + reasoning-effort)'
Ensure-Plugins

if (-not (Test-Path $DshHome)) {
    Warn "DeepSeek Harness app data not found at $DshHome -- install the official app"
    Warn "from https://deepseek.com/harness (or deepseek.com/download) and launch it once, then re-run this if needed."
}

if ($_TmpTemplates) { Remove-Item -Recurse -Force $_TmpTemplates -ErrorAction SilentlyContinue }

Note 'Done.'
Write-Host @"

  Your AI workspace is ready at  $WS  (everything self-contained)

    Python / venv:    $WS\.venv
    crawl4ai MCP:     enabled via the official dsh MCP client (desktop profile)
    Browser:          pre-downloaded to $WS\.browsers
    DSH plugins:      Plugin Market (dshmarket) + reasoning-effort slider

  Remaining steps (2 clicks in the app):
    1. Open DeepSeek Harness -> Settings -> Models -> paste your model API key.
    2. Choose workspace -> $WS

  See  $WS\NEXT-STEPS.md  for details.
"@