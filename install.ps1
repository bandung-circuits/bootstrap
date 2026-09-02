# bootstrap install.ps1 -- LEGACY ENTRY. Kept so the original documented
# one-liner still works after the VS Code + Claude Code scheme moved into
# vscode/. Fetches and runs the vscode scheme verbatim.
# (The DSH Desktop path has its own page: dsh-desktop.html)
#
#   irm https://bandung-circuits.github.io/bootstrap/install.ps1 | iex

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$code = (Invoke-WebRequest 'https://bandung-circuits.github.io/bootstrap/vscode/install.ps1').Content
Invoke-Expression ($code -join "`n")