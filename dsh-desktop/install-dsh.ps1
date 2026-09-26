# dsh-desktop/install-dsh.ps1 -- shared front half for BOTH learner entries
# (public dsh-desktop/setup.ps1 and dsh-desktop/cohort/cohort-setup.ps1):
# ensure DSH Desktop itself is installed.
#
# If the app is missing, downloads the PINNED release (DshVersion below -- the
# version the flow is tested against) from the official GitHub Releases and
# installs it fully silently (NSIS /S, per-user, no admin prompt, no windows)
# -- the same proven method dsh-desktop/ci used. The install takes a few
# minutes; the entries calling this one say so beforehand and nothing is
# required from the learner.
#
# This file is the SINGLE SOURCE OF TRUTH for the version pin. Bump
# deliberately after verifying a new version with the flow. Run as a child
# script, never dot-sourced.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$DshVersion = if ($env:DSH_VERSION) { $env:DSH_VERSION } else { 'v0.9.2' }

function Note($m) { Write-Host "==> $m" }
function Err($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

$dshExe = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop\DSH Desktop.exe'),
  (Join-Path $env:ProgramFiles  'DSH Desktop\DSH Desktop.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($dshExe) {
  Note "DSH Desktop already installed: $dshExe"
  exit 0
}

$url = "https://github.com/dataelement/dsh-desktop/releases/download/$DshVersion/dsh-desktop-windows-x64-setup.exe"
Note "Installing DSH Desktop $DshVersion -- one-time, about 5 minutes total (download ~162 MB, then a fully automatic silent install)."
Note 'No windows will pop up and nothing is required from you; please just let it run.'
$f = Join-Path $env:TEMP 'dsh-desktop-setup.exe'
curl.exe -fL $url -o $f
if ($LASTEXITCODE -ne 0) { Err "download failed: $url" }
Note 'downloaded; installing silently in the background (several minutes, no window)'
$p = Start-Process -FilePath $f -ArgumentList '/S' -Wait -PassThru
if ($p.ExitCode -ne 0) { Err "installer failed (exit $($p.ExitCode))" }
$installedExe = @(
  (Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop\DSH Desktop.exe'),
  (Join-Path $env:ProgramFiles  'DSH Desktop\DSH Desktop.exe')
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $installedExe) {
  Err 'installer finished but the app was not found in the usual locations'
}
Note "DSH Desktop installed: $installedExe"
