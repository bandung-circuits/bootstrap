# Start DeepSeek Harness (dsh) Web UI in this workspace.
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File start-dsh.ps1
Set-Location $PSScriptRoot
$env:DSH_HOME = Join-Path $PWD '.dsh'
if (-not (Get-Command dsh -ErrorAction SilentlyContinue)) {
    Write-Host 'dsh is not installed. Re-run the installer, then try again.'
    exit 1
}
Write-Host 'Starting DeepSeek Harness ... (browser opens at http://127.0.0.1:3080)'
dsh web @args