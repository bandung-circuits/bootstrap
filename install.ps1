# bootstrap install.ps1 -- LEGACY ENTRY. Kept so the original documented
# one-liner still works after the VS Code + Claude Code scheme moved into
# vscode/. It fetches and runs the vscode scheme verbatim; the recommended
# scheme is DeepSeek Harness / dsh
# (https://bandung-circuits.github.io/bootstrap/dsh/install.ps1).
#
#   irm https://bandung-circuits.github.io/bootstrap/install.ps1 | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$code = (Invoke-WebRequest 'https://bandung-circuits.github.io/bootstrap/vscode/install.ps1').Content
Invoke-Expression ($code -join "`n")