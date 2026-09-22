# dsh-desktop/cohort/ci/register-workspace.ps1 -- EXPERIMENT helper (run INSIDE the
# Windows VM). Pre-registers ~/ai-workspace as a workspace in workspace.json with
# NO sessions, so we can observe whether DSH Desktop (a) preserves a pre-written
# workspace.json on launch, and (b) auto-loads/auto-selects a session-less
# workspace. Idempotent; backs up the original once.
param(
  [string]$Path = (Join-Path $env:USERPROFILE 'ai-workspace'),
  [string]$Title = 'ai-workspace'
)
$ErrorActionPreference = 'Stop'

function Get-HarnessHome {
  foreach ($cand in @((Join-Path $env:APPDATA 'dsh-desktop\harness'), (Join-Path $env:APPDATA 'DSH Desktop\harness'))) {
    if (Test-Path $cand) { return $cand }
  }
  return (Join-Path $env:APPDATA 'dsh-desktop\harness')
}
$HARNESS = if ($env:DSH_HOME) { $env:DSH_HOME } else { Get-HarnessHome }
$wsFile = Join-Path $HARNESS 'storages\workspace.json'
$wsDir  = Split-Path $wsFile -Parent
New-Item -ItemType Directory -Force -Path $wsDir | Out-Null

if (-not (Test-Path $Path)) { throw "workspace path does not exist: $Path" }
# canonicalize (realpath) so the app's path canon matches
$canonical = (Get-Item $Path).FullName

$stamp = (Get-Date -Format 'o')
$id = [Guid]::NewGuid().ToString()

if (Test-Path $wsFile) {
  $bak = "$wsFile.dsh-bak"
  if (-not (Test-Path $bak)) { Copy-Item $wsFile $bak }
  $d = Get-Content $wsFile -Raw | ConvertFrom-Json
} else {
  $d = [PSCustomObject]@{
    unit = [PSCustomObject]@{ name = 'workspace'; version = 2 }
    global = [PSCustomObject]@{ initialized = $true; workspaceIds = @(); archivedSessionIds = @() }
    tables = [PSCustomObject]@{ workspaces = [PSCustomObject]@{} }
  }
}

# add/replace the ai-workspace entry (id stable by path)
$existingId = $null
foreach ($k in $d.tables.workspaces.PSObject.Properties.Name) {
  if ($d.tables.workspaces.$k.path -eq $canonical) { $existingId = $k; break }
}
$wid = if ($existingId) { $existingId } else { $id }
$d.tables.workspaces | Add-Member -NotePropertyName $wid -NotePropertyValue ([PSCustomObject]@{
  path = $canonical; title = $Title; sessionIds = @(); createdAt = $stamp; updatedAt = $stamp
}) -Force

$ids = @($d.global.workspaceIds | Where-Object { $_ -ne $wid })
$ids = @($wid) + $ids
$d.global.workspaceIds = $ids

($d | ConvertTo-Json -Depth 10) | Set-Content -Path $wsFile -Encoding UTF8
Write-Host "registered workspace $wid -> $canonical in $wsFile"
