# dsh-desktop/cohort/ci/verify-cohort-windows.ps1 -- run INSIDE the Windows VM
# AFTER cohort-prep.ps1 has run (which ran prep + injected the training
# provider). Asserts the cohort-specific injection in settings.yaml +
# .credentials.yaml, plus a couple of prep sanity checks.
$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0
function OK($m){ Write-Host "  PASS  $m"; $script:pass++ }
function NO($m){ Write-Host "  FAIL  $m"; $script:fail++ }

$WS = Join-Path $env:USERPROFILE 'ai-workspace'
function Get-HarnessHome {
    foreach ($cand in @((Join-Path $env:APPDATA 'dsh-desktop\harness'), (Join-Path $env:APPDATA 'DSH Desktop\harness'))) {
        if (Test-Path $cand) { return $cand }
    }
    return (Join-Path $env:APPDATA 'dsh-desktop\harness')
}
$HARNESS = if ($env:DSH_HOME) { $env:DSH_HOME } else { Get-HarnessHome }
$settings = Join-Path $HARNESS 'settings.yaml'
$creds    = Join-Path $HARNESS '.credentials.yaml'

# --- prep sanity (cohort-prep runs prep first; if these fail, prep broke) ---
foreach ($f in 'AGENTS.md','README.md','.gitignore','NEXT-STEPS.md') {
    if (Test-Path (Join-Path $WS $f)) { OK "prep: $f seeded" } else { NO "prep: $f missing" }
}
$cr4exe = Join-Path $WS '.venv\Scripts\crawl4ai-search.exe'
if (Test-Path $cr4exe) { OK 'prep: crawl4ai executable present' } else { NO 'prep: crawl4ai executable missing' }

# --- cohort injection: settings.yaml ---
$raw = Get-Content $settings -Raw -ErrorAction SilentlyContinue
if (-not $raw) { NO 'settings.yaml not found'; exit 1 }
if ($raw -match 'X-DashScope-DataInspection:\s*''\{"input":"disable","output":"disable"\}''') { OK 'settings: content-inspection header set' } else { NO 'settings: content-inspection header missing' }
if ($raw -match 'apiKeyEnv:\s*TRAINING_API_KEY') { OK 'settings: training provider apiKeyEnv=TRAINING_API_KEY' } else { NO 'settings: apiKeyEnv missing' }
if ($raw -match 'baseURL:\s*https://dashscope\.aliyuncs\.com/compatible-mode/v1') { OK 'settings: training baseURL = Bailian standard endpoint' } else { NO 'settings: baseURL wrong' }
if ($raw -match "provider:\s*training\b" -and $raw -match "model:\s*deepseek-v4-flash-0731") { OK 'settings: agent-default-model -> training/deepseek-v4-flash-0731' } else { NO 'settings: agent-default-model wrong' }

# --- cohort injection: .credentials.yaml ---
$craw = Get-Content $creds -Raw -ErrorAction SilentlyContinue
if (-not $craw) { NO '.credentials.yaml not found'; exit 1 }
if ($craw -match 'TRAINING_API_KEY:\s*''?sk-') { OK 'credentials: TRAINING_API_KEY stored' } else { NO 'credentials: TRAINING_API_KEY missing' }
# the key must match the one passed in (env TRAINING_API_KEY on the verify call)
if ($env:VERIFY_KEY -and $craw -match [regex]::Escape($env:VERIFY_KEY)) { OK 'credentials: key matches the one passed in' } else { NO 'credentials: key mismatch (or VERIFY_KEY not set)' }

# --- pristine backup exists ---
if (Test-Path "$settings.dsh-bak") { OK 'pristine settings backup present (.dsh-bak)' } else { NO 'pristine settings backup missing' }

# --- cohort injection: workspace pre-registration ---
$wsFile = Join-Path $HARNESS 'storages\workspace.json'
if (Test-Path $wsFile) {
  try { $ws = Get-Content $wsFile -Raw | ConvertFrom-Json } catch { $ws = $null }
  if ($ws) {
    $found = $false
    foreach ($k in $ws.tables.workspaces.PSObject.Properties.Name) {
      if ($ws.tables.workspaces.$k.path -match 'ai-workspace') { $found = $true; break }
    }
    if ($found) { OK 'workspace: ai-workspace pre-registered in workspace.json' } else { NO 'workspace: ai-workspace not registered' }
  } else { NO 'workspace.json unreadable' }
} else { NO 'workspace.json not found (not pre-registered)' }

# --- default plugins installed by prep (dshmarket + thinking-effort) ---
$pkgJson = Join-Path $HARNESS 'profiles\web\package.json'
if (Test-Path $pkgJson) {
  try { $pj = Get-Content $pkgJson -Raw | ConvertFrom-Json } catch { $pj = $null }
  if ($pj) {
    $deps = @($pj.dependencies.PSObject.Properties.Name)
    $bundles = @($pj.dsh.profile.bundles)
    if ($deps -contains 'dshmarket' -and $bundles -contains 'dshmarket') { OK 'plugin dshmarket in deps+bundles' } else { NO 'plugin dshmarket missing' }
  } else { NO 'profiles/web/package.json unreadable' }
} else { NO 'profiles/web/package.json not found (plugins not installed)' }

Write-Host ''
Write-Host "RESULT: $pass passed, $fail failed"
exit $fail
