# bootstrap install.ps1 — Windows one-command setup of VS Code + Claude Code +
# DeepSeek V4 Flash 0731, with the crawl4ai MCP. Config lives in ~/ai-workspace
# (self-contained). No Node.js or standalone CLI — the VS Code extension bundles its own.
#
# Usage (PowerShell):
#   irm https://bandung-circuits.github.io/bootstrap/install.ps1 | iex
# or from a clone:
#   .\install.ps1 [-Provider bailian|deepseek|openrouter] [-ApiKey KEY]

#requires -Version 5.1
$ErrorActionPreference = 'Stop'

function Note($m){ Write-Host "==> $m" -ForegroundColor Green }
function Warn($m){ Write-Host "!! $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# ---------- args ----------
$Provider = $null; $ApiKey = $null
for ($i=0; $i -lt $args.Count; $i++) {
    switch -Regex ($args[$i]) {
        '^-?Provider=(.+)$' { $Provider = $matches[1] }
        '^-?ApiKey=(.+)$'   { $ApiKey   = $matches[1] }
        default { Err "unknown argument: $($args[$i])" }
    }
}

# ---------- detect / provider ----------
Note "OS: Windows ($($env:PROCESSOR_ARCHITECTURE))"
if (-not $Provider) {
    $tz = (Get-TimeZone -ErrorAction SilentlyContinue).Id
    $lang = $env:LANG, $env:LC_ALL -join ''
    if ($tz -match 'China|Shanghai|Urumqi' -or $lang -match 'zh_CN|zh_SG') { $Provider = 'bailian' }
    else { $Provider = 'deepseek' }
}
switch ($Provider) {
    'bailian'   { $BaseUrl='https://dashscope.aliyuncs.com/apps/anthropic'; $Model='deepseek-v4-flash-0731' }
    'deepseek'  { $BaseUrl='https://api.deepseek.com/anthropic';            $Model='deepseek-v4-flash' }
    'openrouter'{ $BaseUrl='https://openrouter.ai/api/v1';                  $Model='deepseek/deepseek-v4-flash' }
    default { Err "unknown provider: $Provider" }
}
Note "Provider: $Provider | Base: $BaseUrl | Model: $Model"

if (-not $ApiKey) {
    $p = switch ($Provider) {'bailian'{'Alibaba Cloud Bailian'}'deepseek'{'DeepSeek (platform.deepseek.com)'}'openrouter'{'OpenRouter (openrouter.ai)'}}
    Write-Host "`n  Enter your $p API key (see providers guide on the bootstrap site)."
    $ApiKey = Read-Host '  API key'
    if (-not $ApiKey) { Err 'no API key provided.' }
}

# ---------- paths ----------
$WS = Join-Path $env:USERPROFILE 'ai-workspace'
$Bootstrap = Join-Path $env:USERPROFILE '.bootstrap'
$CrawlDir = Join-Path $Bootstrap 'crawl4ai-mcp-server'
$UV_BIN = Join-Path $env:USERPROFILE '.local\bin\uv.exe'

# ---------- winget helper ----------
function Ensure-Winget {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return }
    Err 'winget not found. Install App Installer from the Microsoft Store, or run on Windows 10 1709+.'
}

# ---------- VS Code ----------
function Install-VSCode {
    if ((Get-Command code -ErrorAction SilentlyContinue) -or (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd")) {
        Note 'VS Code already installed'; return
    }
    Note 'Installing Visual Studio Code (winget)'
    Ensure-Winget
    winget install --id Microsoft.VisualStudioCode -e --accept-source-agreements --accept-package-agreements --silent
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}

# ---------- Claude Code extension ----------
function Install-ClaudeCode {
    $code = Get-Command code -ErrorAction SilentlyContinue
    if (-not $code) { Err "'code' not on PATH. Restart your terminal after VS Code install, then re-run." }
    if (code --list-extensions 2>$null | Select-String -Quiet 'anthropic.claude-code') {
        Note 'Claude Code extension already installed'
    } else {
        Note 'Installing Claude Code VS Code extension'
        code --install-extension anthropic.claude-code --force
    }
}

# ---------- workspace ----------
function New-Workspace {
    if (-not (Test-Path $WS)) { New-Item -ItemType Directory -Force -Path $WS | Out-Null; Note "created $WS" }
    $readme = Join-Path $WS 'README.md'
    if (-not (Test-Path $readme)) {
        @'
# My AI workspace

Default workspace for Claude Code. Open this folder in VS Code, open the Claude Code
panel (Spark icon), and ask, e.g. "create a hello.py and run it".

Backend: DeepSeek V4 Flash 0731. crawl4ai MCP (web fetch/search) is registered.
'@ | Set-Content -Path $readme -Encoding UTF8
    }
    $gi = Join-Path $WS '.gitignore'
    if (-not (Test-Path $gi)) {
        "node_modules/`n.venv/`nvenv/`n__pycache__/`n*.log`n.DS_Store`n.claude/settings.local.json" | Set-Content -Path $gi -Encoding UTF8
    }
}

# ---------- settings.local.json (workspace, self-contained) ----------
function Set-Prop($obj, $name, $value){
    if ($obj.PSObject.Properties.Name -contains $name) { $obj.$name = $value }
    else { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value }
}
function Write-Settings {
    $claudeDir = Join-Path $WS '.claude'
    $settings = Join-Path $claudeDir 'settings.local.json'
    New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
    $data = $null
    if (Test-Path $settings) { try { $data = Get-Content $settings -Raw | ConvertFrom-Json } catch { $data = $null } }
    if (-not $data) { $data = [PSCustomObject]@{} }
    if (-not ($data.PSObject.Properties.Name -contains 'env')) { $data | Add-Member -NotePropertyName env -NotePropertyValue ([PSCustomObject]@{}) }
    Set-Prop $data.env 'ANTHROPIC_BASE_URL'   $BaseUrl
    Set-Prop $data.env 'ANTHROPIC_AUTH_TOKEN' $ApiKey
    Set-Prop $data.env 'ANTHROPIC_MODEL'      $Model
    Set-Prop $data.env 'ANTHROPIC_DEFAULT_SONNET_MODEL' $Model
    Set-Prop $data.env 'ANTHROPIC_DEFAULT_OPUS_MODEL'   $Model
    Set-Prop $data.env 'API_TIMEOUT_MS' '3000000'
    if ($Provider -eq 'bailian') {
        Set-Prop $data.env 'ANTHROPIC_CUSTOM_HEADERS' 'X-DashScope-DataInspection: {"input":"disable","output":"disable"}'
    }
    if (-not ($data.PSObject.Properties.Name -contains 'permissions')) {
        $data | Add-Member -NotePropertyName permissions -NotePropertyValue ([PSCustomObject]@{
            allow = @('Bash(*)','Read','Write','Edit','Glob','Grep','Task','mcp__crawl4ai__search','mcp__crawl4ai__read_url')
            deny  = @('WebSearch','WebFetch')
            ask   = @()
        })
    }
    if (-not ($data.PSObject.Properties.Name -contains 'enabledMcpjsonServers')) {
        $data | Add-Member -NotePropertyName enabledMcpjsonServers -NotePropertyValue @('crawl4ai')
    }
    Set-Prop $data 'hasCompletedOnboarding' $true
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $settings -Encoding UTF8
    Note "wrote $settings"
}

# ---------- uv ----------
function Ensure-Uv {
    if (Test-Path $UV_BIN) { return }
    Note 'Installing uv (Python runtime manager)'
    Ensure-Winget
    winget install --id astral-sh.uv -e --accept-source-agreements --accept-package-agreements --silent
    $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
}

# ---------- crawl4ai MCP ----------
function Install-Crawl4ai {
    $venvPy = Join-Path $CrawlDir 'venv\Scripts\python.exe'
    if ((Test-Path $venvPy) -and (Test-Path (Join-Path $CrawlDir 'src\index.py'))) {
        Note "crawl4ai MCP already installed at $CrawlDir"
    } else {
        Ensure-Winget   # for winget (git via winget below)
        if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
            Note 'Installing Git for Windows (winget)'
            winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements --silent
            $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')
        }
        Ensure-Uv
        $uv = (Get-Command uv -ErrorAction SilentlyContinue).Source
        Note 'Cloning crawl4ai-mcp-server (branch fix/migrate-to-ddgs-library)'
        git clone --branch fix/migrate-to-ddgs-library --depth 1 https://github.com/gigix/crawl4ai-mcp-server.git $CrawlDir
        Note 'Provisioning Python 3.10 + venv via uv (prebuilt wheels for deps)'
        & $uv python install 3.10
        & $uv venv --python 3.10 (Join-Path $CrawlDir 'venv')
        Note 'Installing dependencies via uv (may take a minute)'
        & $uv pip install --python $venvPy -r (Join-Path $CrawlDir 'requirements.txt')
    }

    $mcpFile = Join-Path $WS '.mcp.json'
    $mcp = $null
    if (Test-Path $mcpFile) { try { $mcp = Get-Content $mcpFile -Raw | ConvertFrom-Json } catch { $mcp = $null } }
    if (-not $mcp) { $mcp = [PSCustomObject]@{} }
    if (-not ($mcp.PSObject.Properties.Name -contains 'mcpServers')) { $mcp | Add-Member -NotePropertyName mcpServers -NotePropertyValue ([PSCustomObject]@{}) }
    $entry = [PSCustomObject]@{ command=$venvPy; args=@((Join-Path $CrawlDir 'src\index.py')); cwd=$CrawlDir }
    if ($mcp.mcpServers.PSObject.Properties.Name -contains 'crawl4ai') { $mcp.mcpServers.crawl4ai = $entry }
    else { $mcp.mcpServers | Add-Member -NotePropertyName crawl4ai -NotePropertyValue $entry }
    $mcp | ConvertTo-Json -Depth 10 | Set-Content -Path $mcpFile -Encoding UTF8
    Note "registered crawl4ai in $mcpFile"
    Write-Host "`n  crawl4ai note: first call downloads a headless browser (Playwright). Automatic, no key needed." -ForegroundColor DarkGray
}

# ---------- run ----------
Install-VSCode
Install-ClaudeCode
New-Workspace
Write-Settings
Install-Crawl4ai

Note 'Done.'
Write-Host @'

  Next steps:
  1. Open Visual Studio Code in  ~/ai-workspace  (your default workspace).
  2. Open the Claude Code panel (Spark icon). Backend is already configured to
     DeepSeek V4 Flash 0731 via your API key — no sign-in needed.
  3. Try: "create a hello.py and run it".

  crawl4ai MCP (web fetch/search) is registered. Config lives inside ~/ai-workspace
  (.claude/settings.local.json + .mcp.json), so the workspace is self-contained.
'@
if (Get-Command code -ErrorAction SilentlyContinue) { Start-Process code -ArgumentList "`"$WS`"" }
