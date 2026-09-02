# Start DeepSeek Harness (dsh) Web UI in this workspace.
# Usage:  powershell -NoProfile -ExecutionPolicy Bypass -File start-dsh.ps1
Set-Location $PSScriptRoot
$env:DSH_HOME = Join-Path $PWD '.dsh'

# Load machine-local secrets (dsh refuses launch-control names in its own .env
# files, so they live in secrets.env and we export them into the process env).
$secrets = Join-Path $env:DSH_HOME 'secrets.env'
if (Test-Path $secrets) {
    foreach ($line in Get-Content $secrets) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            [Environment]::SetEnvironmentVariable($matches[1], $matches[2], 'Process')
        }
    }
}
if (-not (Get-Command dsh -ErrorAction SilentlyContinue)) {
    Write-Host 'dsh is not installed. Re-run the installer, then try again.'
    exit 1
}
Write-Host 'Starting DeepSeek Harness ... (browser opens at http://127.0.0.1:3080)'
dsh web @args