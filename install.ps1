# bootstrap install.ps1 -- Windows one-command setup of VS Code + Claude Code +
# DeepSeek V4 Flash 0731, with the crawl4ai MCP. Config lives in ~/ai-workspace
# (self-contained). No Node.js or standalone CLI -- the VS Code extension bundles its own.
#
# deployed: f9a694f5  2026-08-27 16:50:42 +0800 (Beijing)
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

# Run a native command via .NET Process. PS 5.1 under
# $ErrorActionPreference='Stop' wraps native-command stderr (uv progress, node
# deprecation) as a terminating NativeCommandError that can escape a
# function-scope try/catch and kill the whole script. .NET Process.Start is NOT
# a PS native-command invocation, so PS never sees the child's stderr -- no
# NativeCommandError. Stderr/stdout are intentionally NOT redirected: redirecting
# them without draining deadlocks (child blocks on a full pipe under TTY progress).
# Leaving them un-redirected lets output inherit the console (visible progress),
# with no deadlock and no NativeCommandError.
function Invoke-Native([string]$exe, [string]$argStr) {
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo.FileName = $exe
    $p.StartInfo.Arguments = $argStr
    $p.StartInfo.UseShellExecute = $false
    [void]$p.Start()
    $p.WaitForExit()
    return $p.ExitCode
}

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
        $codeExe = $code.Source
        if (-not $codeExe) { $codeExe = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd" }
        $rc = Invoke-Native $codeExe '--install-extension anthropic.claude-code --force'
        if ($rc -ne 0) { throw "Claude Code extension install failed (exit $rc)" }
    }
    # Suppress GitHub Copilot so the only AI chat surface is Claude Code.
    # Best-effort: on a clean VM Copilot isn't installed (and built-in Copilot
    # can't be uninstalled, only disabled via settings in Write-VSCodeUserSettings),
    # so --uninstall-extension returns non-zero ("not installed"). Invoke-Native
    # returns the exit code without throwing, so just ignore it.
    $codeExe2 = ($code.Source)
    if (-not $codeExe2) { $codeExe2 = "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd" }
    foreach ($ext in 'github.copilot','github.copilot-chat') {
        [void](Invoke-Native $codeExe2 "--uninstall-extension $ext")
    }
}

# ---------- workspace ----------
function New-Workspace {
    if (-not (Test-Path $WS)) { New-Item -ItemType Directory -Force -Path $WS | Out-Null; Note "created $WS" }
    $readme = Join-Path $WS 'README.md'
    if (-not (Test-Path $readme)) {
        @'
# My AI workspace

Default workspace for Claude Code. Open this folder in VS Code; the Claude Code
panel is docked in the sidebar (right) and opens with VS Code. Ask, e.g.
"create a hello.py and run it".

Backend: DeepSeek V4 Flash 0731. crawl4ai MCP (web fetch/search) is registered.
'@ | Set-Content -Path $readme -Encoding UTF8
    }
    $gi = Join-Path $WS '.gitignore'
    if (-not (Test-Path $gi)) {
        "node_modules/`n.venv/`nvenv/`n__pycache__/`n*.log`n.DS_Store`n.claude/settings.local.json" | Set-Content -Path $gi -Encoding UTF8
    }
    # workspace .vscode/settings.json -- mirror Claude Code / Copilot settings
    $vsDir = Join-Path $WS '.vscode'
    $vsSettings = Join-Path $vsDir 'settings.json'
    if (-not (Test-Path $vsSettings)) {
        New-Item -ItemType Directory -Force -Path $vsDir | Out-Null
        @'
{
  "claudeCode.preferredLocation": "sidebar",
  "claudeCode.disableLoginPrompt": true,
  "claudeCode.hideOnboarding": true,
  "chat.commandCenter.enabled": false,
  "chat.disableAIFeatures": true,
  "github.copilot.enable": { "*": false }
}
'@ | Set-Content -Path $vsSettings -Encoding UTF8
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

# ---------- VS Code user settings (skip welcome, trust on, Claude Code panel, Copilot off) ----------
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
    Set-Prop $data 'claudeCode.preferredLocation' 'sidebar'
    Set-Prop $data 'claudeCode.disableLoginPrompt' $true
    Set-Prop $data 'claudeCode.hideOnboarding' $true
    Set-Prop $data 'chat.commandCenter.enabled' $false
    Set-Prop $data 'chat.disableAIFeatures' $true
    # NOTE: no workbench.secondarySideBar.defaultVisibility here -- its default
    # ("visibleInWorkspace") plus the seeded UI state show the right sidebar
    # with Claude Code on first launch; "hidden" would collapse it.
    # github.copilot.enable is an object { "*": false }; build it as a map.
    $cop = [PSCustomObject]@{ '*' = $false }
    if ($data.PSObject.Properties.Name -contains 'github.copilot.enable') {
        $data.'github.copilot.enable' = $cop
    } else {
        $data | Add-Member -NotePropertyName 'github.copilot.enable' -NotePropertyValue $cop
    }
    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $settings -Encoding UTF8
    Note 'wrote VS Code user settings (skip welcome, trust on, Claude Code panel + skip login, Copilot off)'
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

The Claude Code panel is docked in the sidebar (right) and opens with VS Code.
It never opens in the center tab by itself. Ask it anything, e.g.  "create a
hello.py and run it".

The crawl4ai MCP (web fetch/search) is already configured -- no key needed.
"@ | Set-Content -Path $steps -Encoding UTF8
    Note "wrote $steps"
}

# ---------- uv ----------
function Ensure-Uv {
    if (Test-Path $UV_BIN) { return }
    Note 'Installing uv (Python runtime manager)'
    # The astral installer refuses to run under a Restricted ExecutionPolicy (its
    # Initialize-Environment throws "requires an execution policy in [...]"), and
    # its top-level catch does `exit 1` -- when iex'd here that kills THIS whole
    # process (exit isn't catchable, so the resilient loop can't log [FAIL] and
    # the window just dies). Run it in a CHILD powershell with
    # -ExecutionPolicy Bypass via Invoke-Native: the child's Bypass passes the
    # check, and its exit only kills the child; we get the exit code and throw
    # on failure (caught by the resilient loop as [FAIL], no flash).
    $installer = Join-Path $env:TEMP 'astral-uv-install.ps1'
    Invoke-WebRequest 'https://astral.sh/uv/install.ps1' -OutFile $installer
    $psExe = Join-Path $PSHOME 'powershell.exe'
    $rc = Invoke-Native $psExe "-NoProfile -ExecutionPolicy Bypass -File `"$installer`""
    if ($rc -ne 0) { throw "uv installer failed (exit $rc)" }
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
        # Run uv via .NET Process (Invoke-Native) so PS 5.1 never sees uv's
        # stderr progress -- under ErrorActionPreference=Stop that becomes a
        # terminating NativeCommandError that crashes the whole script (this
        # was the crawl4ai flash-exit: 6 steps [OK] then the window died).
        $rc = Invoke-Native $uv 'python install 3.10'
        if ($rc -ne 0) { throw "uv python install failed (exit $rc)" }
        $rc = Invoke-Native $uv "venv --python 3.10 `"$CrawlDir\venv`""
        if ($rc -ne 0) { throw "uv venv creation failed (exit $rc)" }
        Note 'Installing dependencies via uv (may take a minute)'
        $rc = Invoke-Native $uv "pip install --python `"$venvPy`" -r `"$CrawlDir\requirements.txt`""
        if ($rc -ne 0) { throw "uv pip install failed (exit $rc)" }
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

# ---------- seed VS Code UI state (onboarding flags + Claude docked RIGHT) ----------
# The "choose interface style"/theme picker on first launch is UI state, not a
# setting -- settings.json can't suppress it. Seed state.vscdb from the captured
# golden template (wip/golden-state.vscdb, portable keys only -- no machine
# paths): welcomeOnboarding.state + newDefaultThemeNotification suppress the
# picker; workbench.auxiliarybar.pinnedPanels +
# workbench.view.extension.claude-sidebar-secondary.state.hidden dock the Claude
# Code view in the RIGHT (secondary) sidebar and auxiliaryBar.empty=false keeps
# the bar non-empty, so with the default secondarySideBar.defaultVisibility
# ("visibleInWorkspace", not set anywhere) the right sidebar OPENS ON FIRST
# LAUNCH with Claude Code in it. Position comes from this UI state
# -- the installer intentionally does NOT auto-open Claude Code via the
# vscode://anthropic.claude-code/open URI, because that handler opens a CENTER
# editor tab (extension's primaryEditor.open, ignores preferredLocation).
# The Anthropic.claude-code flags (walkthrough off) are seeded INSERT OR IGNORE
# (fresh installs only) so re-runs never clobber the extension's own state.
# Uses the crawl4ai venv python (stdlib sqlite3); best-effort (skip if missing).
function Seed-VSCodeState {
    $db = Join-Path $env:APPDATA 'Code\User\globalStorage\state.vscdb'
    $venvPy = Join-Path $CrawlDir 'venv\Scripts\python.exe'
    if (-not (Test-Path $venvPy)) { Note "crawl4ai venv python not found -- skipping VS Code UI-state seed (first-run onboarding may show)"; return }
    $dir = Split-Path $db -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    # Write the seeder to a temp .py and run THAT (not `python -c $py`): PS strips
    # the embedded double-quotes when passing a string to a native -c arg, so
    # python gets `con.execute(CREATE ...` (no quotes) -> SyntaxError. Reading
    # from a file avoids PS's native-arg quote-mangling. Local EAP=Continue so a
    # stray python stderr line doesn't raise a NativeCommandError under Stop.
    $tmp = Join-Path $env:TEMP 'seed-vscode-state.py'
    @'
import sqlite3, os, sys
path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)
con = sqlite3.connect(path)
con.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
# Written on every run (idempotent): first-run flags + Claude docked in the
# right (secondary) sidebar -- values cut 1:1 from wip/golden-state.vscdb.
seeds = {
    "welcomeOnboarding.state": "true",
    "workbench.newDefaultThemeNotification": "true",
    "workbench.auxiliarybar.pinnedPanels": '[{"id":"workbench.panel.chat","pinned":true,"visible":false,"order":1},{"id":"workbench.view.extension.claude-sidebar-secondary","pinned":true,"visible":false,"order":101}]',
    "workbench.view.extension.claude-sidebar-secondary.state.hidden": '[{"id":"claudeVSCodeSidebarSecondary","isHidden":false}]',
    "workbench.auxiliaryBar.empty": "false",
}
# Written only when absent (INSERT OR IGNORE beats the schema's REPLACE):
# Claude Code extension state -- lastClaudeLocationMigrated stops the
# first-activation walkthrough auto-open, tengu_vscode_onboarding:false hides
# the onboarding checklist (from the golden capture).
fresh = {
    "Anthropic.claude-code": '{"settingsMigrated20251024":true,"lastClaudeLocationMigrated":true,"experimentGates":{"tengu_vscode_onboarding":false}}',
}
cur = con.cursor()
for k, v in seeds.items():
    cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (k, v))
for k, v in fresh.items():
    cur.execute("INSERT OR IGNORE INTO ItemTable (key, value) VALUES (?, ?)", (k, v))
con.commit(); con.close()
print("seeded %d VS Code UI-state keys (+%d fresh-only) into %s" % (len(seeds), len(fresh), path))
'@ | Set-Content -Path $tmp -Encoding UTF8
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $venvPy $tmp $db
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($rc -ne 0) { throw "VS Code UI-state seed failed (python exit $rc)" }
    Note "seeded VS Code UI-state (skip onboarding; Claude Code docked in the right sidebar)"
}

# ---------- run (resilient: each step in try/catch, one failure doesn't abort the rest) ----------
$ErrorActionPreference = 'Stop'
$steps = @(
    @{ Name='Visual Studio Code';          Action={ Install-VSCode } },
    @{ Name='Claude Code extension';       Action={ Install-ClaudeCode } },
    @{ Name='VS Code user settings';       Action={ Write-VSCodeUserSettings } },
    @{ Name='AI workspace';                Action={ New-Workspace } },
    @{ Name='settings.local.json';         Action={ Write-Settings } },
    @{ Name='NEXT-STEPS.md';               Action={ Write-NextSteps } },
    @{ Name='crawl4ai MCP';                Action={ Install-Crawl4ai } },
    @{ Name='VS Code UI-state seed';       Action={ Seed-VSCodeState } }
)
$failed = @()
$logFile = Join-Path $env:USERPROFILE 'bootstrap-install.log'
"bootstrap install -- $(Get-Date)" | Out-File $logFile -Encoding UTF8
foreach ($s in $steps) {
    try { & $s.Action; "[OK] $($s.Name)" | Out-File $logFile -Encoding UTF8 -Append }
    catch {
        $msg = "[FAIL] $($s.Name) -- $($_.Exception.Message)"
        Warn $msg
        $msg | Out-File $logFile -Encoding UTF8 -Append
        $failed += $s.Name
    }
}

Note 'Done.'
if ($failed.Count -gt 0) {
    Warn ("Some steps failed (the rest still ran): " + ($failed -join ', '))
    Write-Host '  Re-run the script to retry failed steps, or open ~/ai-workspace/NEXT-STEPS.md.' -ForegroundColor Yellow
} else {
    Write-Host '  All steps completed.' -ForegroundColor Green
}
Write-Host @'

  Almost ready! One step left: add your API key.
  See  ~/ai-workspace/NEXT-STEPS.md  (where to get a key, which file to edit,
  and how to start Claude Code).

  Then open VS Code in  ~/ai-workspace  -- Claude Code opens in the right
  sidebar, ready to use.
  crawl4ai MCP (web fetch/search) is registered and ready.
'@
# CI runs the installer over SSH with no desktop session; launching VS Code
# (a GUI) there spins and can freeze the VM. run-test.sh sets
# BOOTSTRAP_NO_LAUNCH=1 to skip. Real users (desktop terminal) want the launch.
if ($env:BOOTSTRAP_NO_LAUNCH -eq '1') {
    Note 'skipping VS Code launch (BOOTSTRAP_NO_LAUNCH=1)'
} elseif (Get-Command code -ErrorAction SilentlyContinue) {
    # Open the workspace folder (loads .claude/.mcp.json/.vscode) and
    # NEXT-STEPS.md (the file with the API-key instructions). Deliberately NO
    # vscode://anthropic.claude-code/open here: that URI resolves to the
    # extension's primaryEditor.open command and opens Claude Code in a CENTER
    # editor tab, ignoring claudeCode.preferredLocation (official docs: "open a
    # new Claude Code tab"; upstream issue anthropics/claude-code#89511). The
    # Claude view is docked in the right sidebar by the seeded UI state
    # (Seed-VSCodeState) instead; the user opens it with the Spark icon.
    Start-Process code -ArgumentList "`"$WS`"", "`"$(Join-Path $WS 'NEXT-STEPS.md')`""
}
