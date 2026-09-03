# dsh-desktop/prep.ps1 -- one-command workspace prep for DSH Desktop (Windows).
#
# deployed:  (stamped by ci/deploy-pages.yml)
#
# Usage (PowerShell):
#   irm https://bandung-circuits.github.io/bootstrap/dsh-desktop/prep.ps1 | iex
# or from a clone:
#   .\dsh-desktop\prep.ps1
#
# Prerequisite: DSH Desktop installed (https://dshdesktop.com/en/). Platforms:
# macOS + Windows only (the app has no Linux build).
#
# What it does:
#   1. Creates %USERPROFILE%\ai-workspace and seeds AGENTS.md / README.md /
#      .gitignore / NEXT-STEPS.md (existing files are left alone).
#   2. Installs uv/uvx (the runner the crawl4ai MCP uses).
#   3. Enables the crawl4ai MCP server through the OFFICIAL
#      @deepseek-ai/dsh-mcp-client (bundled with DSH Desktop -- no plugin install)
#      by appending one insert to the app's harness patch
#      %APPDATA%\DSH Desktop\harness\cordis.patch.yml.
#
# The model backend key is entered by the learner in the app (Settings -> Models).

#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$REPO_RAW = 'https://bandung-circuits.github.io/bootstrap/dsh-desktop'
$_TmpTemplates = ''

function Note($m){ Write-Host "==> $m" -ForegroundColor Green }
function Warn($m){ Write-Host "!! $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# ---------- paths (env-overridable for tests) ----------
$WS   = if ($env:WORKSPACE_DIR) { $env:WORKSPACE_DIR } else { Join-Path $env:USERPROFILE 'ai-workspace' }
$AppData = Join-Path $env:APPDATA 'DSH Desktop'
$HARNESS = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $AppData 'harness' }
$UV_DIR  = if ($env:UV_DIR) { $env:UV_DIR } else { Join-Path $env:USERPROFILE '.local\bin' }
$UVX     = Join-Path $UV_DIR 'uvx.exe'

function Refresh-UVPath {
    $env:Path = "$UV_DIR;" + $env:Path
}

# ---------- templates ----------
function Get-Templates {
    $here = Split-Path -Parent $PSCommandPath
    $local = Join-Path $here 'templates'
    if (Test-Path (Join-Path $local 'workspace')) {
        $script:TW = Join-Path $local 'workspace'
        $script:TP = Join-Path $local 'dsh-desktop'
        return
    }
    $_TmpTemplates = Join-Path $env:TEMP ("dshdesktop-tpl-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path (Join-Path $_TmpTemplates 'workspace'), (Join-Path $_TmpTemplates 'dsh-desktop') | Out-Null
    foreach ($f in 'AGENTS.md','README.md','_gitignore','NEXT-STEPS.md') {
        Invoke-WebRequest "$REPO_RAW/templates/workspace/$f" -OutFile (Join-Path $_TmpTemplates "workspace\$f") -TimeoutSec 30
    }
    Invoke-WebRequest "$REPO_RAW/templates/dsh-desktop/crawl4ai-patch.yml" -OutFile (Join-Path $_TmpTemplates 'dsh-desktop\crawl4ai-patch.yml') -TimeoutSec 30
    $script:TW = Join-Path $_TmpTemplates 'workspace'
    $script:TP = Join-Path $_TmpTemplates 'dsh-desktop'
}

# ---------- 1. workspace ----------
function Seed-Workspace {
    New-Item -ItemType Directory -Force -Path $WS | Out-Null
    # template-name:installed-name (template names never equal installed names)
    $map = @('AGENTS.md:AGENTS.md','README.md:README.md','_gitignore:.gitignore','NEXT-STEPS.md:NEXT-STEPS.md')
    foreach ($m in $map) {
        $src = $m.Split(':')[0]; $dst = $m.Split(':')[1]
        $path = Join-Path $WS $dst
        if (Test-Path $path) { Note "kept existing $path"; continue }
        Copy-Item (Join-Path $script:TW $src) $path
        Note "seeded $path"
    }
}

# ---------- 2. uv/uvx ----------
function Ensure-Uv {
    if (Test-Path $UVX) { Note "uvx present ($UVX)"; return }
    if ($env:PREP_NO_UV -eq '1') { Note 'skipping uv install (PREP_NO_UV=1)'; return }
    Note 'Installing uv/uvx (the runner crawl4ai uses)'
    $installer = Join-Path $env:TEMP 'astral-uv-install.ps1'
    Invoke-WebRequest 'https://astral.sh/uv/install.ps1' -OutFile $installer -TimeoutSec 60
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $p = Start-Process -FilePath $psExe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$installer`"" -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { Err "uv installer failed (exit $($p.ExitCode))" }
    if (-not (Test-Path $UVX)) { Err "uvx not found at $UVX" }
    Refresh-UVPath
    Note 'uv installed'
}

# ---------- 3. crawl4ai MCP (official mcp-client) ----------
function Ensure-McpCrawl4ai {
    New-Item -ItemType Directory -Force -Path $HARNESS | Out-Null
    $patch = Join-Path $HARNESS 'cordis.patch.yml'
    if ((Test-Path $patch) -and (Select-String -Path $patch -SimpleMatch 'mcp-crawl4ai' -Quiet)) {
        Note "crawl4ai MCP already enabled in $patch"
        return
    }
    if (-not (Test-Path $UVX)) { Err "uvx not found at $UVX -- run the uv step first" }
    $block = (Get-Content -Raw (Join-Path $script:TP 'crawl4ai-patch.yml'))
    $block = $block.Replace('{{UVX_BIN}}', $UVX).Replace('{{WORKSPACE}}', $WS)
    Add-Content -Path $patch -Value "`n# DSH Desktop harness home-level patch (applies to every profile)$([char]10)$block" -Encoding UTF8
    Note "enabled crawl4ai MCP in $patch"
}

# ---------- main ----------
Get-Templates
Note 'Creating and seeding the AI workspace'
Seed-Workspace
Note 'Installing uv/uvx (crawl4ai runtime)'
Ensure-Uv
Note 'Enabling crawl4ai MCP (official DSH mcp-client)'
Ensure-McpCrawl4ai

if (-not (Test-Path $AppData)) {
    Warn "DSH Desktop app data not found at $AppData -- install DSH Desktop"
    Warn "from https://dshdesktop.com/en/ and launch it once, then re-run this if needed."
}

if ($_TmpTemplates) { Remove-Item -Recurse -Force $_TmpTemplates -ErrorAction SilentlyContinue }

Note 'Done.'
Write-Host @"

  Your AI workspace is ready at  $WS

  Remaining steps (2 clicks in the app):
    1. Open DSH Desktop -> Settings -> Models -> paste your DeepSeek API key.
    2. Choose workspace -> $WS

  The crawl4ai MCP (web fetch/search) is enabled through the official DSH MCP
  client. First search downloads a small helper environment automatically.

  See  $WS\NEXT-STEPS.md  for details.
"@