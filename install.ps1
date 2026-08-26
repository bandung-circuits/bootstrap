# bootstrap install.ps1 -- Windows one-command setup of VS Code + Claude Code +
# DeepSeek V4 Flash 0731, with the crawl4ai MCP. Config lives in ~/ai-workspace
# (self-contained). No Node.js or standalone CLI -- the VS Code extension bundles its own.
#
# Usage (PowerShell):
#   irm https://bandung-circuits.github.io/bootstrap/install.ps1 | iex
# or from a clone:
#   .\install.ps1 [-Provider bailian|bailian-intl|deepseek|openrouter] [-ApiKey KEY]
# Args accept both -Provider=val and -Provider val forms.

#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # speed up Invoke-WebRequest

function Note($m){ Write-Host "==> $m" -ForegroundColor Green }
function Warn($m){ Write-Host "!! $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# ---------- args (accept -Key=val and -Key val) ----------
$Provider = $null; $ApiKey = $null
for ($i=0; $i -lt $args.Count; $i++) {
    $a = $args[$i]
    switch -Regex ($a) {
        '^-?Provider=(.+)$' { $Provider = $matches[1] }
        '^-?ApiKey=(.+)$'   { $ApiKey   = $matches[1] }
        '^-?Provider$'      { $Provider = $args[++$i] }
        '^-?ApiKey$'        { $ApiKey   = $args[++$i] }
        default { Err "unknown argument: $a" }
    }
}

# ---------- detect / provider ----------
Note "OS: Windows ($($env:PROCESSOR_ARCHITECTURE))"
if (-not $Provider) {
    $tz = (Get-TimeZone -ErrorAction SilentlyContinue).Id
    $lang = $env:LANG, $env:LC_ALL -join ''
    if ($tz -match 'China|Shanghai|Urumqi' -or $lang -match 'zh_CN|zh_SG') { $Provider = 'bailian' }
    else { $Provider = 'bailian-intl' }
}
switch ($Provider) {
    'bailian'      { $BaseUrl='https://dashscope.aliyuncs.com/apps/anthropic';     $Model='deepseek-v4-flash-0731' }
    'bailian-intl' { $BaseUrl='https://dashscope-intl.aliyuncs.com/apps/anthropic'; $Model='deepseek-v4-flash' }
    'deepseek'     { $BaseUrl='https://api.deepseek.com/anthropic';                $Model='deepseek-v4-flash' }
    'openrouter'   { $BaseUrl='https://openrouter.ai/api/v1';                      $Model='deepseek/deepseek-v4-flash' }
    default { Err "unknown provider: $Provider" }
}
Note "Provider: $Provider | Base: $BaseUrl | Model: $Model"
if (-not $ApiKey) { $ApiKey = 'PASTE-YOUR-API-KEY-HERE'; $script:KeyIsPlaceholder = $true }
else { $script:KeyIsPlaceholder = $false }

# ---------- paths ----------
$WS = Join-Path $env:USERPROFILE 'ai-workspace'
$Bootstrap = Join-Path $env:USERPROFILE '.bootstrap'
$CrawlDir = Join-Path $Bootstrap 'crawl4ai-mcp-server'
$UV_BIN = Join-Path $env:USERPROFILE '.local\bin\uv.exe'

function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') + ';' + $env:USERPROFILE + '\.local\bin' }

# ---------- VS Code (direct download, no winget) ----------
function Install-VSCode {
    if ((Get-Command code -ErrorAction SilentlyContinue) -or (Test-Path "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd")) {
        Note 'VS Code already installed'; return
    }
    Note 'Installing Visual Studio Code (ARM64 user installer, no winget)'
    $url = 'https://update.code.visualstudio.com/latest/win32-arm64-user/stable'
    $exe = Join-Path $env:TEMP 'vscode-setup.exe'
    Invoke-WebRequest $url -OutFile $exe
    Start-Process $exe -ArgumentList '/VERYSILENT','/NORESTART','/MERGETASKS=!runcode' -Wait
    Refresh-Path
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
    $claudeMd = Join-Path $WS 'CLAUDE.md'
    if (-not (Test-Path $claudeMd)) {
        @'
# CLAUDE.md -- workspace rules for Claude Code

## Web tools: prefer crawl4ai
Prefer the crawl4ai MCP (mcp__crawl4ai__read_url / mcp__crawl4ai__search) for
web fetch/search -- free, no key. If unavailable, fall back to WebFetch / WebSearch.

## Grounded search (avoid hallucination)
Never trust a search summary alone. Fetch the real page/PDF in full with
mcp__crawl4ai__read_url and read it before answering. Cite the source URL.

## Backend
This workspace talks to DeepSeek V4 Flash 0731 via .claude/settings.local.json
(where you pasted your API key). No Anthropic sign-in needed.
'@ | Set-Content -Path $claudeMd -Encoding UTF8
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
    if ($Provider -eq 'bailian' -or $Provider -eq 'bailian-intl') {
        Set-Prop $data.env 'ANTHROPIC_CUSTOM_HEADERS' 'X-DashScope-DataInspection: {"input":"disable","output":"disable"}'
    }
    if (-not ($data.PSObject.Properties.Name -contains 'permissions')) {
        $data | Add-Member -NotePropertyName permissions -NotePropertyValue ([PSCustomObject]@{
            allow = @('Bash(*)','Read','Write','Edit','Glob','Grep','Task','mcp__crawl4ai__search','mcp__crawl4ai__read_url')
            deny  = @()
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

# ---------- VS Code user settings (skip welcome, trust on, Claude Code = Edit automatically) ----------
function Write-VSCodeUserSettings {
    $dir = Join-Path $env:APPDATA 'Code\User'
    $settings = Join-Path $dir 'settings.json'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $data = $null
    if (Test-Path $settings) { try { $data = Get-Content $settings -Raw | ConvertFrom-Json } catch { $data = $null } }
    if (-not $data) { $data = [PSCustomObject]@{} }
    Set-Prop $data 'workbench.startupEditor' 'none'
    Set-Prop $data 'workbench.welcomePage.walkthroughsVisible' $false
    Set-Prop $data 'update.showReleaseNotes' $false
    Set-Prop $data 'security.workspace.trust.enabled' $false
    Set-Prop $data 'claudeCode.initialPermissionMode' 'acceptEdits'
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $settings -Encoding UTF8
    Note 'wrote VS Code user settings (skip welcome, trust on, Claude Code = Edit automatically)'
}

# ---------- NEXT-STEPS.md ----------
function Write-NextSteps {
    $p_site = switch ($Provider) {
        'bailian'      { 'https://bailian.console.aliyun.com/' }
        'bailian-intl' { 'https://dashscope-intl.console.aliyun.com/' }
        'deepseek'     { 'https://platform.deepseek.com/' }
        'openrouter'   { 'https://openrouter.ai/' }
    }
    $p_name = switch ($Provider) {
        'bailian'      { 'Alibaba Cloud Bailian (China)' }
        'bailian-intl' { 'Alibaba Cloud Model Studio (international)' }
        'deepseek'     { 'DeepSeek' }
        'openrouter'   { 'OpenRouter' }
    }
    $keyNote = if ($script:KeyIsPlaceholder) { '' } else { "`n(Note: an API key was already provided to the installer -- skip the paste step if that's the key you intend to use.)" }
    $steps = Join-Path $WS 'NEXT-STEPS.md'
    @"
# Next steps

Your AI workspace is set up at  $WS
One thing left: add your API key, then start using Claude Code.

## 1. Get an API key

Get a key for DeepSeek V4 Flash 0731 from ${p_name}:
  $p_site
(Full guide: https://bandung-circuits.github.io/bootstrap/providers-guide.html )

## 2. Paste your key into the config

Open this file:
  $WS\.claude\settings.local.json

Find the line:
  "ANTHROPIC_AUTH_TOKEN": "PASTE-YOUR-API-KEY-HERE"

Replace  PASTE-YOUR-API-KEY-HERE  with your real key. Save the file.$keyNote

## 3. Start using Claude Code

Open VS Code in this workspace:
  code $WS

Click the Spark icon (top-right of the editor, or in the sidebar) to open the
Claude Code panel. Ask it anything, e.g.  "create a hello.py and run it".

The crawl4ai MCP (web fetch/search) is already configured -- no key needed.
"@ | Set-Content -Path $steps -Encoding UTF8
    Note "wrote $steps"
}

# ---------- uv ----------
function Ensure-Uv {
    if (Test-Path $UV_BIN) { return }
    Note 'Installing uv (Python runtime manager)'
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    Refresh-Path
}

# ---------- crawl4ai MCP (download zip, no git; uv venv) ----------
function Install-Crawl4ai {
    $venvPy = Join-Path $CrawlDir 'venv\Scripts\python.exe'
    if ((Test-Path $venvPy) -and (Test-Path (Join-Path $CrawlDir 'src\index.py'))) {
        Note "crawl4ai MCP already installed at $CrawlDir"
    } else {
        Ensure-Uv
        New-Item -ItemType Directory -Force -Path $Bootstrap | Out-Null
        $zip = Join-Path $env:TEMP 'crawl4ai-mcp.zip'
        Note 'Downloading crawl4ai-mcp-server (branch fix/migrate-to-ddgs-library)'
        Invoke-WebRequest 'https://github.com/gigix/crawl4ai-mcp-server/archive/refs/heads/fix/migrate-to-ddgs-library.zip' -OutFile $zip
        if (Test-Path $CrawlDir) { Remove-Item -Recurse -Force $CrawlDir }
        Expand-Archive -Path $zip -DestinationPath $Bootstrap -Force
        # extracted folder has a -suffix name; rename to crawl4ai-mcp-server
        $extracted = Get-ChildItem -Path $Bootstrap -Directory | Where-Object Name -like 'crawl4ai-mcp-server-*' | Select-Object -First 1
        if ($extracted) { Move-Item $extracted.FullName $CrawlDir -Force }
        Note 'Provisioning Python 3.10 + venv via uv (prebuilt wheels for deps)'
        $uv = (Get-Command uv -ErrorAction SilentlyContinue).Source
        if (-not $uv) { $uv = $UV_BIN }
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
Write-VSCodeUserSettings
New-Workspace
Write-Settings
Write-NextSteps
Install-Crawl4ai

Note 'Done.'
Write-Host @'

  Almost ready! One step left: add your API key.
  See  ~/ai-workspace/NEXT-STEPS.md  (where to get a key, which file to edit,
  and how to start Claude Code).

  Then open VS Code in  ~/ai-workspace  and click the Spark icon.
  crawl4ai MCP (web fetch/search) is registered and ready.
'@
if (Get-Command code -ErrorAction SilentlyContinue) { Start-Process code -ArgumentList "`"$WS`"" }
