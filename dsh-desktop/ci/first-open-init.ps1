# first-open-init.ps1 -- CI helper: simulate the official DeepSeek Harness app's
# FIRST OPEN so its desktop profile (~/.dsh/profiles/<name>/package.json) gets
# initialized. The official desktop refuses `dsh plugin --profile <name> add`
# until the app has been opened once; CI can't click, so it launches the app
# hidden, waits for the profile to appear, then quits it. Safe to re-run; no-op
# if already initialized. Non-fatal if it times out (the plugin step then stays
# deferred, matching prep's design) -- return 0 regardless.
#
# Run on a Windows machine/VM where the official app is installed.
param([string]$ProfileName = 'desktop')
$ErrorActionPreference = 'Continue'
$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $env:USERPROFILE '.dsh' }
$prof = Join-Path $DshHome "profiles\$ProfileName\package.json"
if (Test-Path $prof) { Write-Host "profile already initialized: $prof"; exit 0 }
$exe = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe'),
  (Join-Path $env:ProgramFiles  'DeepSeek Harness\DeepSeek Harness.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $exe) { Write-Host 'DeepSeek Harness.exe not found; cannot initialize profile'; exit 0 }
Write-Host "first open (headless): launching $exe to initialize profile '$ProfileName'"
Start-Process $exe -WindowStyle Hidden | Out-Null
# Give the app up to ~2 min to materialize the profile (first run can be slow).
for ($i = 0; $i -lt 40 -and -not (Test-Path $prof); $i++) { Start-Sleep -Seconds 3 }
Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
# Wait until every app process is really gone, or the later prep plugin step
# sees "DeepSeek Harness is running" and skips the plugin install.
for ($i = 0; $i -lt 10; $i++) {
    if (-not (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Seconds 3
}
if (Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue) {
    Write-Host 'WARN: DeepSeek Harness processes still running after quit -- the later plugin step will be skipped'
}
if (Test-Path $prof) { Write-Host "profile initialized after first open: $prof"; exit 0 }
Write-Host 'WARN: profile not initialized within timeout (app first-run may need an interactive screen) -- plugins will be deferred'
exit 0