# dsh-desktop/cohort/cohort-setup.ps1 -- full learner setup for a training
# cohort (Windows). One command, nothing pre-installed:
#
#   $env:TRAINING_API_KEY='sk-...'; iex (curl.exe -sL https://bandung-circuits.github.io/bootstrap/dsh-desktop/cohort/cohort-setup.ps1 | Out-String)
#
# 1. Ensures DSH Desktop is installed -- the shared front half
#    (../install-dsh.ps1, pinned release, fully silent /S) does this; this
#    script holds no install logic and no version pin.
# 2. Delegates everything else to cohort-prep.ps1 VERBATIM (public prep +
#    provider/key injection).
#
# macOS uses cohort-setup.sh.

$ErrorActionPreference = 'Stop'

$repoBase = 'https://bandung-circuits.github.io/bootstrap'
$CohortPrepUrl = if ($env:COHORT_PREP_URL) { $env:COHORT_PREP_URL } else { "$repoBase/dsh-desktop/cohort/cohort-prep.ps1" }
$InstallDshUrl = if ($env:INSTALL_DSH_URL) { $env:INSTALL_DSH_URL } else { "$repoBase/dsh-desktop/install-dsh.ps1" }

function Note($m) { Write-Host "==> $m" }
function Err($m) { Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# 0. fail fast on a missing key BEFORE downloading a ~162 MB installer.
if (-not $env:TRAINING_API_KEY -or $env:TRAINING_API_KEY -eq '') {
  Err 'TRAINING_API_KEY is missing -- copy the command from your cohort page, not a generic one.'
}

# 1. DSH Desktop itself (pinned, fully silent) -- shared front half.
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot '..\install-dsh.ps1'))) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\install-dsh.ps1')
} else {
  Invoke-Expression (curl.exe -sL $InstallDshUrl | Out-String)
}

# 2. everything else is exactly the existing cohort flow (public prep + inject).
# REUSE -- no setup logic here. Env (key, model, ...) flows through.
Note 'Running the cohort workspace setup (workspace, web tools, model provider)'
if (Test-Path $CohortPrepUrl) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File $CohortPrepUrl
} else {
  Invoke-Expression (curl.exe -sL $CohortPrepUrl | Out-String)
}
