# dsh-desktop/ci/install-windows.ps1 — ensure DSH Desktop is installed in the
# Windows VM (used by ci/run-test-dsh-desktop.sh). Idempotent.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$app = Join-Path $env:LOCALAPPDATA 'Programs\DSH Desktop'
if (Test-Path (Join-Path $app 'DSH Desktop.exe')) {
    Write-Host 'DSH Desktop already installed'
    exit 0
}
$url = if ($env:DSH_DESKTOP_WIN_URL) { $env:DSH_DESKTOP_WIN_URL } else {
    'https://github.com/dataelement/dsh-desktop/releases/download/v0.7.1/dsh-desktop-windows-x64-setup.exe'
}
$f = Join-Path $env:TEMP 'dsh-desktop-setup.exe'
Write-Host "downloading $url"
Invoke-WebRequest $url -OutFile $f -TimeoutSec 600
Write-Host ("downloaded " + (Get-Item $f).Length + " bytes; installing silently")
$p = Start-Process -FilePath $f -ArgumentList '/S' -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "installer failed (exit $($p.ExitCode))" }
Write-Host 'DSH Desktop installed'