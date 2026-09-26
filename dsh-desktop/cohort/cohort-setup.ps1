# dsh-desktop/cohort/cohort-setup.ps1 -- full learner setup for a training
# cohort (Windows). One command, nothing pre-installed:
#
#   $env:TRAINING_API_KEY='sk-...'; iex (curl.exe -sL https://bandung-circuits.github.io/bootstrap/dsh-desktop/cohort/cohort-setup.ps1 | Out-String)
#
# 1. Ensures DSH Desktop is installed: if the app is missing, downloads the
#    PINNED release (DshVersion below -- the version the cohort flow is tested
#    against) from the official GitHub Releases and installs it silently
#    (NSIS /S, per-user, no admin prompt) -- same proven method as
#    dsh-desktop/ci/install-windows.ps1.
# 2. Delegates everything else to cohort-prep.ps1 VERBATIM (public prep +
#    provider/key injection), so this script adds no setup logic of its own.
#
# macOS uses cohort-setup.sh. The public (non-cohort) flow does NOT use this
# script: it still asks learners to install DSH Desktop by hand first.
#
# NOTE on the pin: it only controls what WE install on a fresh machine. The
# app's own auto-updater still offers newer versions afterwards, and harness
# config survives app upgrades -- same exposure as the manual-install flow.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoBase = 'https://bandung-circuits.github.io/bootstrap'
$CohortPrepUrl = if ($env:COHORT_PREP_URL) { $env:COHORT_PREP_URL } else { "$repoBase/dsh-desktop/cohort/cohort-prep.ps1" }

# Pinned DSH Desktop release. Bump deliberately, after the cohort flow has been
# verified against the new version (see cohort/README.md "Pinned DSH Desktop
# version"). Env-overridable for tests.
$DshVersion = if ($env:DSH_VERSION) { $env:DSH_VERSION } else { 'v0.9.2' }

function Note($m) { Write-Host "==> $m" }
function Err($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# 0. fail fast on a missing key BEFORE downloading a ~163 MB installer.
if (-not $env:TRAINING_API_KEY -or $env:TRAINING_API_KEY -eq '') {
  Err 'TRAINING_API_KEY is missing -- copy the command from your cohort page, not a generic one.'
}

# 1. DSH Desktop present? (per-user install is the norm; check Program Files too)
$dshExe = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop\DSH Desktop.exe'),
  (Join-Path $env:ProgramFiles  'DSH Desktop\DSH Desktop.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($dshExe) {
  Note "DSH Desktop already installed: $dshExe"
} else {
  $url = "https://github.com/dataelement/dsh-desktop/releases/download/$DshVersion/dsh-desktop-windows-x64-setup.exe"
  Note "Installing DSH Desktop $DshVersion (~162 MB, one-time)"
  $f = Join-Path $env:TEMP 'dsh-desktop-setup.exe'
  curl.exe -fL $url -o $f
  if ($LASTEXITCODE -ne 0) { Err "download failed: $url" }
  Note 'downloaded; installing silently (no wizard, under a minute)'
  $p = Start-Process -FilePath $f -ArgumentList '/S' -Wait -PassThru
  if ($p.ExitCode -ne 0) { Err "installer failed (exit $($p.ExitCode))" }
  if (-not (Test-Path (Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop\DSH Desktop.exe'))) {
    Err 'installer finished but the app was not found where expected'
  }
  Note 'DSH Desktop installed'
}

# 2. everything else is exactly the existing cohort flow (public prep + inject).
# REUSE -- no setup logic here. Env (key, model, ...) flows through. Same dual
# form as cohort-prep.ps1: local file path (CI) or URL (learner).
Note 'Running the cohort workspace setup (workspace, web tools, model provider)'
if (Test-Path $CohortPrepUrl) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $CohortPrepUrl
} else {
  Invoke-Expression (curl.exe -sL $CohortPrepUrl | Out-String)
}
