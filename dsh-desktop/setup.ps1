# dsh-desktop/setup.ps1 -- one-command bootstrap for DSH Desktop learners
# (public, Windows). Nothing pre-installed:
#
#   iex (curl.exe -sL https://bandung-circuits.github.io/bootstrap/dsh-desktop/setup.ps1 | Out-String)
#
# 1. Ensures DSH Desktop itself is installed (pinned release, fully silent)
#    by running install-dsh.ps1 -- the shared front half with the cohort flow.
# 2. Delegates everything else to prep.ps1 VERBATIM (workspace, venv +
#    crawl4ai, browser, crawl4ai MCP, permission default) -- no setup logic
#    here. The model API key is intentionally NOT handled: the learner
#    pastes their own key in the app afterwards (Settings -> Models).
#
# macOS uses setup.sh. The training-cohort flow additionally injects a shared
# provider key (cohort/cohort-setup.ps1) and is maintained separately.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$repoBase = 'https://bandung-circuits.github.io/bootstrap'
$PrepUrl = if ($env:PREP_URL) { $env:PREP_URL } else { "$repoBase/dsh-desktop/prep.ps1" }

# 1. DSH Desktop itself (pinned) -- shared front half.
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'install-dsh.ps1'))) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'install-dsh.ps1')
} else {
  Invoke-Expression (curl.exe -sL "$repoBase/dsh-desktop/install-dsh.ps1" | Out-String)
}

# 2. The workspace (public prep). REUSE -- no setup logic here.
Write-Host '==> Setting up the AI workspace (workspace, web tools)'
if (Test-Path $PrepUrl) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $PrepUrl
} else {
  Invoke-Expression (curl.exe -sL $PrepUrl | Out-String)
}

# 3. The end line learners are told to look for on the setup page. Keep the
#    text identical to the "how it ends when it worked" sample shown there
#    (same banner in setup.sh, setup.ps1, cohort-setup.sh, cohort-setup.ps1).
#    ASCII-only: Windows PowerShell 5.1 parses BOM-less files as ANSI.
Write-Host @'

  ============================================
    Setup complete!
    Now open the DSH Desktop app
    (Mac: Launchpad  |  Windows: Start menu)
  ============================================
'@ -ForegroundColor Green
