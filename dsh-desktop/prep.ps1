# dsh-desktop/prep.ps1 -- one-command workspace prep for DSH Desktop (Windows).
#
# deployed:  (stamped by ci/deploy-pages.yml)
#
# Usage (PowerShell):
#   iex (curl.exe -sL https://bandung-circuits.github.io/bootstrap/dsh-desktop/prep.ps1 | Out-String)
# or from a clone:
#   .\dsh-desktop\prep.ps1
#
# Prerequisite: DSH Desktop installed (https://dshdesktop.com/en/). Platforms:
# macOS + Windows only (the app has no Linux build).
#
# Everything is installed INSIDE the workspace so the app's subprocesses can
# find it without ~\.local\bin (not on PATH) or ~\.crawl4ai:
#   %USERPROFILE%\ai-workspace\
#     AGENTS.md README.md .gitignore NEXT-STEPS.md   seeds
#     .venv\                       python + crawl4ai-search-mcp pre-installed
#     .browsers\                   Playwright Chromium (pre-downloaded)
#     .crawl4ai\                   crawl4ai data
#     .local\bin\                  uv (helper, not needed at runtime)
#
# The crawl4ai MCP server runs the workspace venv's crawl4ai-search.exe by
# absolute path. The app's harness data stays in %APPDATA%\DSH Desktop\harness;
# the model key is entered by the learner in the app.

#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$REPO_RAW = 'https://bandung-circuits.github.io/bootstrap/dsh-desktop'
$_TmpTemplates = ''

function Note($m){ Write-Host "==> $m" -ForegroundColor Green }
function Warn($m){ Write-Host "!! $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# ---------- paths (env-overridable for tests; PSCommandPath is $null under iex) ----------
$WS     = if ($env:WORKSPACE_DIR) { $env:WORKSPACE_DIR } else { Join-Path $env:USERPROFILE 'ai-workspace' }
$AppData = Join-Path $env:APPDATA 'DSH Desktop'
$HARNESS = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $AppData 'harness' }
$UV      = Join-Path $WS '.local\bin\uv.exe'
$VENV_PY = Join-Path $WS '.venv\Scripts\python.exe'
$BROWSER = Join-Path $WS '.browsers'
$CR4     = Join-Path $WS '.venv\Scripts\crawl4ai-search.exe'

# ---------- templates ----------
function Get-Templates {
    $here = ''
    if ($PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
    if ($here -and (Test-Path (Join-Path $here 'templates\workspace'))) {
        $script:TW = Join-Path $here 'templates\workspace'
        $script:TP = Join-Path $here 'templates\dsh-desktop'
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

# ---------- 1. workspace seeds ----------
function Seed-Workspace {
    New-Item -ItemType Directory -Force -Path $WS | Out-Null
    $map = @('AGENTS.md:AGENTS.md','README.md:README.md','_gitignore:.gitignore','NEXT-STEPS.md:NEXT-STEPS.md')
    foreach ($m in $map) {
        $src = $m.Split(':')[0]; $dst = $m.Split(':')[1]
        $path = Join-Path $WS $dst
        if (Test-Path $path) { Note "kept existing $path"; continue }
        Copy-Item (Join-Path $script:TW $src) $path
        Note "seeded $path"
    }
}

# ---------- 2. uv into the workspace ----------
function Ensure-Uv {
    if (Test-Path $UV) { Note "uv present ($UV)"; return }
    if ($env:PREP_NO_UV -eq '1') { Note 'skipping uv install (PREP_NO_UV=1)'; return }
    Note "Installing uv into $($WS)\.local\bin"
    New-Item -ItemType Directory -Force -Path (Split-Path $UV -Parent) | Out-Null
    $installer = Join-Path $env:TEMP 'astral-uv-install.ps1'
    Invoke-WebRequest 'https://astral.sh/uv/install.ps1' -OutFile $installer -TimeoutSec 60
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $env:UV_INSTALL_DIR = Split-Path $UV -Parent
    $p = Start-Process -FilePath $psExe -ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$installer`"" -Wait -PassThru -NoNewWindow
    if ($p.ExitCode -ne 0) { Err "uv installer failed (exit $($p.ExitCode))" }
    Remove-Item Env:UV_INSTALL_DIR -ErrorAction SilentlyContinue
    if (-not (Test-Path $UV)) { Err "uv not found at $UV" }
    Note 'uv installed'
}

# ---------- 3. venv + crawl4ai-search-mcp, all inside the workspace ----------
function Ensure-Venv {
    Ensure-Uv
    if (-not (Test-Path $CR4)) {
        Note "Creating venv and installing crawl4ai-search-mcp==0.1.1"
        & $UV venv (Join-Path $WS '.venv')
        & $UV pip install -p (Join-Path $WS '.venv') 'crawl4ai-search-mcp==0.1.1'
    }
    if (-not (Test-Path $CR4)) { Err "crawl4ai-search not found at $CR4" }
    Note "crawl4ai-search at $CR4"
}

# ---------- 4. pre-download the Playwright Chromium into the workspace ----------
function Ensure-Browser {
    $probe = Get-ChildItem $BROWSER -Recurse -Filter 'chrome.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($probe) { Note "browser already present in $BROWSER"; return }
    if ($env:PREP_NO_BROWSER -eq '1') { Note 'skipping browser pre-download (PREP_NO_BROWSER=1)'; return }
    Note "Pre-downloading the Chromium browser into $BROWSER"
    New-Item -ItemType Directory -Force -Path $BROWSER | Out-Null
    $env:PLAYWRIGHT_BROWSERS_PATH = $BROWSER
    try {
        & $VENV_PY -m playwright install chromium | Out-Null
        Note 'browser ready'
    } catch {
        Warn "browser pre-download failed: $($_.Exception.Message) -- first search will download it automatically"
    }
    Remove-Item Env:PLAYWRIGHT_BROWSERS_PATH -ErrorAction SilentlyContinue
}

# ---------- 5. crawl4ai MCP (official mcp-client), self-contained ----------
function Ensure-McpCrawl4ai {
    New-Item -ItemType Directory -Force -Path $HARNESS | Out-Null
    $patch = Join-Path $HARNESS 'cordis.patch.yml'
    if ((Test-Path $patch) -and (Select-String -Path $patch -SimpleMatch 'mcp-crawl4ai' -Quiet)) {
        Note "crawl4ai MCP already enabled in $patch"
        return
    }
    $block = (Get-Content -Raw (Join-Path $script:TP 'crawl4ai-patch.yml'))
    $block = $block.Replace('{{CRAWL4AI_BIN}}', $CR4).Replace('{{WORKSPACE}}', $WS)
    Add-Content -Path $patch -Value "`n# DSH Desktop harness home-level patch (applies to every profile)$([char]10)$block" -Encoding UTF8
    Note "enabled crawl4ai MCP in $patch"
}

# ---------- main ----------
Get-Templates
Note 'Creating and seeding the AI workspace'
Seed-Workspace
Note 'Installing uv into the workspace'
Ensure-Uv
Note 'Creating the workspace venv with crawl4ai'
Ensure-Venv
Note 'Pre-downloading the Chromium browser'
Ensure-Browser
Note 'Enabling crawl4ai MCP (official DSH mcp-client)'
Ensure-McpCrawl4ai

if (-not (Test-Path $AppData)) {
    Warn "DSH Desktop app data not found at $AppData -- install DSH Desktop"
    Warn "from https://dshdesktop.com/en/ and launch it once, then re-run this if needed."
}

if ($_TmpTemplates) { Remove-Item -Recurse -Force $_TmpTemplates -ErrorAction SilentlyContinue }

Note 'Done.'
Write-Host @"

  Your AI workspace is ready at  $WS  (everything self-contained)

    Python / venv:    $WS\.venv
    crawl4ai MCP:     enabled via the official DSH MCP client
    Browser:          pre-downloaded to $WS\.browsers

  Remaining steps (2 clicks in the app):
    1. Open DSH Desktop -> Settings -> Models -> paste your model API key.
    2. Choose workspace -> $WS

  See  $WS\NEXT-STEPS.md  for details.
"@