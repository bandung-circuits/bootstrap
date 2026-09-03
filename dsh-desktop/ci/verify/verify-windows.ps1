# dsh-desktop/ci/verify/verify-windows.ps1 — run INSIDE the Windows VM AFTER the
# DSH Desktop app has been installed and dsh-desktop/prep.ps1 has run.
# Asserts: workspace seeds, the crawl4ai patch in the app's harness data, and
# that the app's bundled harness composes the patch (dump-config).
$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0
function OK($m){ Write-Host "  PASS  $m"; $script:pass++ }
function NO($m){ Write-Host "  FAIL  $m"; $script:fail++ }

$WS     = Join-Path $env:USERPROFILE 'ai-workspace'
$HARNESS = Join-Path $env:APPDATA 'DSH Desktop\harness'
$patch  = Join-Path $HARNESS 'cordis.patch.yml'

# --- seeds ---
foreach ($f in 'AGENTS.md','README.md','.gitignore','NEXT-STEPS.md') {
    if (Test-Path (Join-Path $WS $f)) { OK "$f seeded" } else { NO "$f seeded" }
}

# --- patch ---
$pc = Get-Content $patch -Raw -ErrorAction SilentlyContinue
if ($pc -match 'mcp-crawl4ai' -and $pc -match '@deepseek-ai/dsh-mcp-client' -and $pc -match 'crawl4ai-search-mcp==0.1.1' -and $pc -match '\.local\\bin\\uvx\.exe') {
    OK 'patch enables crawl4ai (official mcp-client, pinned, abs uvx)'
} else {
    NO 'patch shape wrong — see below'
    Write-Host ($pc.Substring(0,[Math]::Min(400,[string]$pc.Length)))
}

# --- bundled harness composes the patch ---
$node = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop') -Recurse -Filter 'node.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
$dsh  = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop') -Recurse -Filter 'bin.js' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -match '[@_]deepseek' -and $_.FullName -match '\\dsh\\' } | Select-Object -First 1
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