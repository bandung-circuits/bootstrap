# dsh-desktop/cohort/cohort-prep.ps1 -- training-cohort one-command setup (Windows).
#
# Learner runs (the key is baked into the command on the cohort HTML page):
#   $env:TRAINING_API_KEY='sk-...'; iex (curl.exe -sL https://bandung-circuits.github.io/bootstrap/dsh-desktop/cohort/cohort-prep.ps1 | Out-String)
#
# Prerequisite: DSH Desktop installed (https://dshdesktop.com/en/). Windows only
# here; macOS uses cohort-prep.sh.
#
# REUSES the public dsh-desktop/prep.ps1 verbatim for the workspace, venv +
# crawl4ai, the crawl4ai MCP, and the Full Access permission default, then calls
# inject_provider.py to add the Bailian `training` provider (key + the
# content-inspection header documented at
# https://extremeprogramming-cn.github.io/bailian-content-inspection/) and pin
# `agent-default-model` to the cohort model (deepseek-v4-flash-0731). The learner
# only has to open the app and pick ~\ai-workspace.

$ErrorActionPreference = 'Stop'

$repoBase = 'https://bandung-circuits.github.io/bootstrap'
$PrepUrl  = if ($env:PREP_URL)  { $env:PREP_URL }  else { "$repoBase/dsh-desktop/prep.ps1" }
$InjectUrl = if ($env:INJECT_URL) { $env:INJECT_URL } else { "$repoBase/dsh-desktop/cohort/inject_provider.py" }
$Model       = if ($env:MODEL)        { $env:MODEL }        else { 'deepseek-v4-flash-0731' }
$BaseUrl     = if ($env:BASE_URL)     { $env:BASE_URL }     else { 'https://dashscope.aliyuncs.com/compatible-mode/v1' }
$Label       = if ($env:LABEL)        { $env:LABEL }        else { 'Training' }
$ProviderId  = if ($env:PROVIDER_ID)  { $env:PROVIDER_ID }  else { 'training' }

function Note($m) { Write-Host "==> $m" }
function Warn_($m) { Write-Host "!! $m" -ForegroundColor Yellow }
function Err($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# 0. key must be present.
if (-not $env:TRAINING_API_KEY -or $env:TRAINING_API_KEY -eq '') {
  Err 'TRAINING_API_KEY is missing -- copy the command from your cohort page, not a generic one.'
}

# 0.5. DSH Desktop must not be running while we write its config. If the app is
# open, it holds settings.yaml in memory and will overwrite our injection on
# quit. Kill it (the learner was told to quit, but enforce it).
$procs = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match 'DSH\s*Desktop' })
if ($procs.Count -gt 0) {
  Note 'DSH Desktop is running -- closing it so the config writes are not overwritten'
  $procs | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 2
}

# 1. locate the DSH Desktop harness data dir (mirrors prep.ps1's Get-HarnessHome).
function Get-HarnessHome {
  foreach ($cand in @((Join-Path $env:APPDATA 'dsh-desktop\harness'), (Join-Path $env:APPDATA 'DSH Desktop\harness'))) {
    if (Test-Path $cand) { return $cand }
  }
  return (Join-Path $env:APPDATA 'dsh-desktop\harness')
}
$HARNESS = if ($env:DSH_HOME) { $env:DSH_HOME } else { Get-HarnessHome }

# 2. pristine backup of the two files we will touch, BEFORE prep runs.
foreach ($f in @((Join-Path $HARNESS 'settings.yaml'), (Join-Path $HARNESS '.credentials.yaml'))) {
  if (Test-Path $f) {
    $bak = "$f.dsh-bak"
    if (-not (Test-Path $bak)) {
      New-Item -ItemType Directory -Force -Path $HARNESS | Out-Null
      Copy-Item $f $bak
      Note "backed up $f -> $bak"
    }
  }
}

# 3. run the public prep (workspace, venv, crawl4ai MCP, Full Access). REUSE.
# curl.exe returns an Object[] of lines; iex needs a single string, so pipe
# through Out-String (same pattern as dsh-desktop/ci/run-prep.ps1).
Note 'Running the standard workspace prep'
if (Test-Path $PrepUrl) {
  & powershell -NoProfile -File $PrepUrl
} else {
  Invoke-Expression (curl.exe -sL $PrepUrl | Out-String)
}

# 4. Use the workspace venv's python by ABSOLUTE PATH. prep just created it; the
# dsh-desktop design is fully self-contained in ~\ai-workspace (no PATH lookup,
# no system python, no Microsoft Store "App execution alias" stub).
$PyExe = Join-Path $HOME 'ai-workspace\.venv\Scripts\python.exe'
if (-not (Test-Path $PyExe)) {
  Err "workspace venv python not found at $PyExe -- prep did not complete. Re-run the command from your cohort page."
}

# 5. run the provider/key/header/default-model injection (single source of truth).
Note 'Configuring the training provider, key, and default model'
$injectArgs = @(
  '--harness-home', $HARNESS,
  '--key', $env:TRAINING_API_KEY,
  '--base-url', $BaseUrl,
  '--model', $Model,
  '--label', $Label,
  '--provider-id', $ProviderId,
  '--workspace', (Join-Path $HOME 'ai-workspace')
)
if (Test-Path $InjectUrl) {
  & $PyExe $InjectUrl @injectArgs
} else {
  $tmp = [System.IO.Path]::GetTempFileName() + '.py'
  try {
    curl.exe -sL $InjectUrl -o $tmp
    & $PyExe $tmp @injectArgs
  } finally {
    Remove-Item $tmp -ErrorAction SilentlyContinue
  }
}

Note 'Done.'

Write-Host ''
Write-Host "  Your AI workspace is ready at  ~\ai-workspace  -- everything is set up:"
Write-Host ''
Write-Host "    Model:            $Model  (via $ProviderId provider, Bailian)"
Write-Host "    API key:          already configured -- you do NOT paste anything in the app"
Write-Host "    Content safety:   platform-side inspection header set to avoid false blocks"
Write-Host "    Permission:       Full Access (the agent can work without prompting you)"
Write-Host "    crawl4ai MCP:     enabled (web fetch + search, free, no key)"
Write-Host ''
Write-Host '  Last step (one click in the app):'
Write-Host '    1. Open DSH Desktop.'
Write-Host '    2. Choose workspace ->  ~\ai-workspace'
Write-Host '    3. Start asking. The model is already selected.'
Write-Host ''
Write-Host '  Note: this key is shared by everyone in your cohort and expires after the'
Write-Host '  training. Keep it on the page you were given; do not post it publicly.'
