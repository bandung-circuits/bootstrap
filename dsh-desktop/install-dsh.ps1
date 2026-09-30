# dsh-desktop/install-dsh.ps1 -- shared front half for BOTH learner entries
# (public dsh-desktop/setup.ps1 and dsh-desktop/cohort/cohort-setup.ps1):
# ensure the official DeepSeek Harness desktop app is installed.
#
# The OFFICIAL desktop app is "DeepSeek Harness" (deepseek-ai/deepseek-harness,
# apps: apps/desktop), Windows x64 only, downloaded from DeepSeek's own CDN
# (always-current pointer dsh-latest-windows-x64.exe). We record the observed
# version (DshVersion below) as the pin; the app's own updater still offers
# newer versions afterwards and it uses the same ~/.dsh data root, so harness
# config survives upgrades. NSIS /S, per-user, no admin prompt, no windows.
#
# This file is the SINGLE SOURCE OF TRUTH for the version pin on Windows; keep
# DshVersion agreeing with install-dsh.sh and cohort/generate.py (the cohort
# smoke checks all three). Bump deliberately after re-verifying the new build.
# Run as a child script, never dot-sourced.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Observed from dsh-latest-windows-x64.exe, kept in sync with install-dsh.sh.
$DshVersion = if ($env:DSH_VERSION) { $env:DSH_VERSION } else { '0.2.0-rc.2' }
$DshUrl     = if ($env:DSH_DMG_URL) { $env:DSH_DMG_URL } else { 'https://download.deepseek.com/desktop/dsh-latest-windows-x64.exe' }

function Note($m) { Write-Host "==> $m" }
function Err($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# Official NSIS per-user install lands under Programs\DeepSeek Harness.
# Multiple spellings so a ProgramFiles (all-users) install is also caught.
$dshExe = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe'),
  (Join-Path $env:ProgramFiles  'DeepSeek Harness\DeepSeek Harness.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($dshExe) {
  Note "DeepSeek Harness already installed: $dshExe"
  exit 0
}

Note "Installing DeepSeek Harness (official) $DshVersion -- one-time, about 5 minutes total (download ~276 MB, then a fully automatic silent install)."
Note 'No windows will pop up and nothing is required from you; please just let it run.'
$f = Join-Path $env:TEMP 'dsh-harness-setup.exe'
curl.exe -fL $DshUrl -o $f
if ($LASTEXITCODE -ne 0) { Err "download failed: $DshUrl" }
Note 'downloaded; installing silently in the background (several minutes, no window)'
$p = Start-Process -FilePath $f -ArgumentList '/S' -Wait -PassThru
if ($p.ExitCode -ne 0) { Err "installer failed (exit $($p.ExitCode))" }
$installedExe = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe'),
  (Join-Path $env:ProgramFiles  'DeepSeek Harness\DeepSeek Harness.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $installedExe) {
  Err 'installer finished but the app was not found in the usual locations'
}
Note "DeepSeek Harness installed: $installedExe"