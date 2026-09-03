# dsh-desktop/ci/verify/verify-windows.ps1 — run INSIDE the Windows VM AFTER the
# DSH Desktop app has been installed and dsh-desktop/prep.ps1 has run.
# Asserts: workspace seeds, in-workspace venv with crawl4ai, the crawl4ai patch
# pointing at the workspace venv (with in-workspace browsers/data env), and that
# the app's bundled harness composes the patch (dump-config).
$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0
function OK($m){ Write-Host "  PASS  $m"; $script:pass++ }
function NO($m){ Write-Host "  FAIL  $m"; $script:fail++ }

$WS      = Join-Path $env:USERPROFILE 'ai-workspace'
$HARNESS = Join-Path $env:APPDATA 'DSH Desktop\harness'
$patch   = Join-Path $HARNESS 'cordis.patch.yml'
$venvPy  = Join-Path $WS '.venv\Scripts\python.exe'
$cr4exe  = Join-Path $WS '.venv\Scripts\crawl4ai-search.exe'

# --- seeds ---
foreach ($f in 'AGENTS.md','README.md','.gitignore','NEXT-STEPS.md') {
    if (Test-Path (Join-Path $WS $f)) { OK "$f seeded" } else { NO "$f seeded" }
}

# --- in-workspace python + crawl4ai ---
if ((Test-Path $venvPy) -and (& $venvPy -c 'import crawl4ai_mcp_server' 2>&1 | Out-Null; $LASTEXITCODE -eq 0)) {
    OK 'venv python imports crawl4ai_mcp_server (in-workspace)'
} else {
    NO 'workspace venv missing or crawl4ai_mcp_server not importable'
}
if (Test-Path $cr4exe) { OK "crawl4ai executable present ($cr4exe)" } else { NO 'crawl4ai executable missing' }

# --- patch ---
$pc = Get-Content $patch -Raw -ErrorAction SilentlyContinue
if ($pc -match 'mcp-crawl4ai' -and $pc -match '@deepseek-ai/dsh-mcp-client' -and $pc -match [regex]::Escape("command: $cr4exe") -and $pc -match 'CRAWL4_AI_BASE_DIRECTORY' -and $pc -match 'PLAYWRIGHT_BROWSERS_PATH') {
    OK 'patch: official mcp-client -> workspace venv + in-workspace browsers/data'
} else {
    NO 'patch shape wrong — see below'
    Write-Host ($pc.Substring(0,[Math]::Min(400,[string]$pc.Length)))
}

# --- bundled harness composes the patch ---
$node = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop') -Recurse -Filter 'node.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$dsh  = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop') -Recurse -Filter 'bin.js' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '@deepseek-ai' -and $_.FullName -match '\\dsh\\' } | Select-Object -First 1
if ($node -and $dsh) {
    $env:DSH_HOME = $HARNESS
    $out = & $node.FullName $dsh.FullName web --dump-config 2>&1 | Out-String
    if ($out -match 'mcp-crawl4ai') { OK 'bundled DSH harness composes mcp-crawl4ai (dump-config)' } else { NO 'bundled harness did not compose mcp-crawl4ai' }
} else {
    NO "bundled harness not found (node=$($node.FullName), dsh=$($dsh.FullName))"
}

Write-Host ''
Write-Host "RESULT: $pass passed, $fail failed"
exit $fail