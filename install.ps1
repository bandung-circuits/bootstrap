# bootstrap install.ps1 — Windows one-command setup of VS Code + Claude Code + DeepSeek V4 Flash 0731.
#
# Usage (PowerShell):
#   irm https://bandung-circuits.github.io/bootstrap/install.ps1 | iex
# or from a clone:
#   .\install.ps1 [-Provider bailian|deepseek|openrouter] [-ApiKey KEY]
#
# Requires Windows 10/11 (ARM64 or x64). Uses winget for VS Code + Node.

#requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Note($m){ Write-Host "==> $m" -ForegroundColor Green }
function Warn($m){ Write-Host "!! $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# ---------- arg parsing ----------
$Provider = $null
$ApiKey = $null
for ($i=0; $i -lt $args.Count; $i++) {
    switch -Regex ($args[$i]) {
        '^-?Provider=(.+)$' { $Provider = $matches[1] }
        '^-?ApiKey=(.+)$'   { $ApiKey   = $matches[1] }
        default { Err "unknown argument: $($args[$i])" }
    }
}

# ---------- detect ----------
$IsArm = $env:PROCESSOR_ARCHITECTURE -match 'ARM'
Note "OS: Windows ($($env:PROCESSOR_ARCHITECTURE))"

# Region default: China -> bailian, else deepseek.
if (-not $Provider) {
    $tz = (Get-TimeZone -ErrorAction SilentlyContinue).Id
    $lang = $env:LANG, $env:LC_ALL -join ''
    if ($tz -match 'China|Shanghai|Urumqi' -or $lang -match 'zh_CN|zh_SG') {
        $Provider = 'bailian'
    } else {
        $Provider = 'deepseek'
    }
}

switch ($Provider) {
    'bailian'   { $BaseUrl='https://dashscope.aliyuncs.com/apps/anthropic'; $Model='deepseek-v4-flash-0731' }
    'deepseek'  { $BaseUrl='https://api.deepseek.com/anthropic';            $Model='deepseek-v4-flash' }
    'openrouter'{ $BaseUrl='https://openrouter.ai/api/v1';                  $Model='deepseek/deepseek-v4-flash' }
    default { Err "unknown provider: $Provider" }
}
Note "Provider: $Provider | Base: $BaseUrl | Model: $Model"

# ---------- api key ----------
if (-not $ApiKey) {
    $p = switch ($Provider) {'bailian'{'Alibaba Cloud Bailian'}'deepseek'{'DeepSeek (platform.deepseek.com)'}'openrouter'{'OpenRouter (openrouter.ai)'}}
    Write-Host "`n  Enter your $p API key (see providers guide on the bootstrap site)."
    $ApiKey = Read-Host '  API key'
    if (-not $ApiKey) { Err 'no API key provided.' }
}

# ---------- winget helper ----------
function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    Err 'winget not found. Install App Installer from the Microsoft Store, or run this on Windows 10 1709+.'
}

# ---------- VS Code ----------
function Install-VSCode {
    $code = Get-Command code -ErrorAction SilentlyContinue
    if (-not $code) {
        $exe = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd"
        if (Test-Path $exe) {
            $code = $exe  # pseudo
        }
    }
    if ($code) { Note 'VS Code already installed'; return }
    Note 'Installing Visual Studio Code (winget)'
    Ensure-Winget
    winget install --id Microsoft.VisualStudioCode -e --accept-source-agreements --accept-package-agreements --silent
    # refresh PATH for this session
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}

# ---------- Node ----------
function Install-Node {
    if (Get-Command node -ErrorAction SilentlyContinue) { Note "Node.js already installed ($(node --version))"; return }
    Note 'Installing Node.js (winget)'
    Ensure-Winget
    winget install --id OpenJS.NodeJS -e --accept-source-agreements --accept-package-agreements --silent
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}

# ---------- Claude Code ----------
function Install-ClaudeCode {
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Note 'Claude Code CLI already installed'
    } else {
        Note 'Installing Claude Code CLI (npm)'
        npm install -g @anthropic-ai/claude-code
    }
    $codeCmd = Get-Command code -ErrorAction SilentlyContinue
    if (-not $codeCmd) { Err "'code' not on PATH. Restart your terminal/VS Code install, then re-run." }
    Note 'Installing Claude Code VS Code extension'
    code --install-extension anthropic.claude-code --force
}

# ---------- settings.json (PS 5.1-safe JSON merge via PSCustomObject) ----------
function Set-Prop($obj, $name, $value){
    if ($obj.PSObject.Properties.Name -contains $name) {
        $obj.$name = $value
    } else {
        $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value
    }
}
function Write-Settings {
    $claudeDir = Join-Path $env:USERPROFILE '.claude'
    $settings = Join-Path $claudeDir 'settings.json'
    New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null

    $data = $null
    if (Test-Path $settings) {
        try { $data = Get-Content $settings -Raw | ConvertFrom-Json } catch { $data = $null }
    }
    if (-not $data) { $data = [PSCustomObject]@{} }
    if (-not ($data.PSObject.Properties.Name -contains 'env')) {
        $data | Add-Member -NotePropertyName env -NotePropertyValue ([PSCustomObject]@{})
    }
    Set-Prop $data.env 'ANTHROPIC_BASE_URL'   $BaseUrl
    Set-Prop $data.env 'ANTHROPIC_AUTH_TOKEN' $ApiKey
    Set-Prop $data.env 'ANTHROPIC_MODEL'      $Model
    Set-Prop $data 'hasCompletedOnboarding' $true
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $settings -Encoding UTF8
    Note "wrote $settings"
}

# ---------- crawl4ai MCP ----------
function Install-Crawl4ai {
    $srvDir = Join-Path $env:USERPROFILE '.bootstrap\crawl4ai-mcp-server'
    $venvPy = Join-Path $srvDir 'venv\Scripts\python.exe'
    if ((Test-Path $venvPy) -and (Test-Path (Join-Path $srvDir 'src\index.py'))) {
        Note "crawl4ai MCP already installed at $srvDir"
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $srvDir) | Out-Null
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Err 'git not found; install Git for Windows first.' }
        if (-not (Get-Command python -ErrorAction SilentlyContinue) -and -not (Get-Command python3 -ErrorAction SilentlyContinue)) { Err 'python not found; install Python 3 first.' }
        Note 'Cloning crawl4ai-mcp-server'
        git clone --depth 1 https://github.com/gigix/crawl4ai-mcp-server.git $srvDir
        $py = (Get-Command python -ErrorAction SilentlyContinue)
        if (-not $py) { $py = Get-Command python3 }
        Note 'Creating venv'
        & $py.Source -m venv (Join-Path $srvDir 'venv')
        $pip = Join-Path $srvDir 'venv\Scripts\pip.exe'
        Note 'Installing dependencies (this can take a minute)'
        & $pip install --upgrade pip -q
        & $pip install -r (Join-Path $srvDir 'requirements.txt') -q
    }

    $mcpFile = Join-Path $env:USERPROFILE '.claude\.mcp.json'
    $claudeDir = Join-Path $env:USERPROFILE '.claude'
    New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
    $mcp = $null
    if (Test-Path $mcpFile) {
        try { $mcp = Get-Content $mcpFile -Raw | ConvertFrom-Json } catch { $mcp = $null }
    }
    if (-not $mcp) { $mcp = [PSCustomObject]@{} }
    if (-not ($mcp.PSObject.Properties.Name -contains 'mcpServers')) {
        $mcp | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([PSCustomObject]@{})
    }
    $entry = [PSCustomObject]@{ command=$venvPy; args=@((Join-Path $srvDir 'src\index.py')); cwd=$srvDir }
    if ($mcp.mcpServers.PSObject.Properties.Name -contains 'crawl4ai') {
        $mcp.mcpServers.crawl4ai = $entry
    } else {
        $mcp.mcpServers | Add-Member -NotePropertyName crawl4ai -NotePropertyValue $entry
    }
    $mcp | ConvertTo-Json -Depth 10 | Set-Content -Path $mcpFile -Encoding UTF8
    Note "registered crawl4ai in $mcpFile"
    Write-Host "`n  crawl4ai note: first call downloads a headless browser (Playwright). Automatic, no key needed." -ForegroundColor DarkGray
}

# ---------- workspace ----------
function New-Workspace {
    $ws = Join-Path $env:USERPROFILE 'ai-workspace'
    if (-not (Test-Path $ws)) {
        New-Item -ItemType Directory -Force -Path $ws | Out-Null
        Note "created workspace at $ws"
    }
    $readme = Join-Path $ws 'README.md'
    if (-not (Test-Path $readme)) {
        @'
# My AI workspace

This folder is your default workspace for Claude Code. Keep your projects here.

## Quick start

1. Open this folder in VS Code.
2. Open the Claude Code panel (sidebar).
3. Tell the AI what you want, e.g.:
   - "create a hello.py and run it"
   - "find recent news about <topic> and save it to news.md"
   - "explain what's in this folder"

The backend is DeepSeek V4 Flash 0731. The crawl4ai MCP (web fetch/search) is ready.
'@ | Set-Content -Path $readme -Encoding UTF8
        Note "seeded $readme"
    }
    $gi = Join-Path $ws '.gitignore'
    if (-not (Test-Path $gi)) {
        "node_modules/`n.venv/`nvenv/`n__pycache__/`n*.log`n.DS_Store" | Set-Content -Path $gi -Encoding UTF8
    }
    # open VS Code there (best-effort)
    if (Get-Command code -ErrorAction SilentlyContinue) {
        Note "opening VS Code in $ws"
        Start-Process code -ArgumentList "`"$ws`""
    }
    return $ws
}

# ---------- run ----------
Install-VSCode
Install-Node
Install-ClaudeCode
Write-Settings
Install-Crawl4ai
$ws = New-Workspace

Note 'Done.'
Write-Host @'

  Next steps:
  1. Visual Studio Code opens in  ~/ai-workspace  (your default workspace).
  2. Open the Claude Code panel (sidebar). Backend is already configured to
     DeepSeek V4 Flash 0731 via your API key.
  3. Run  /model  to confirm the active model.
  4. Try: "create a hello.py and run it".

  crawl4ai MCP (web fetch/search) is registered and ready.
'@
