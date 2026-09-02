# bootstrap dsh/install.ps1 -- Windows one-command setup of DeepSeek Harness
# (dsh) + DeepSeek V4 Flash 0731 + the crawl4ai MCP, in ~/ai-workspace.
#
# deployed:  (stamped by ci/deploy-pages.yml)
#
# Usage (PowerShell):
#   irm https://bandung-circuits.github.io/bootstrap/dsh/install.ps1 | iex
# or from a clone:
#   .\dsh\install.ps1 [-Provider bailian|bailian-intl|deepseek|openrouter] [-ApiKey KEY]
#
# Notes:
#   - Uses winget to install Node.js LTS if a supported Node is missing
#     (engine requirement: ^22.19.0 || >=24.0.0).
#   - dsh is pinned:  @deepseek-ai/dsh@0.1.1-rc.2
#   - Config lives in  ~\ai-workspace\.dsh\  (settings.yaml, secrets.env, cordis.patch.yml
#     with the crawl4ai MCP row). Templates are fetched from the same GitHub
#     Pages origin; the installer never embeds config text.

#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$REPO_RAW = 'https://bandung-circuits.github.io/bootstrap/dsh'
$ROOT_RAW = 'https://bandung-circuits.github.io/bootstrap'
$DSH_NPM_PKG = '@deepseek-ai/dsh@0.1.1-rc.2'

function Note($m){ Write-Host "==> $m" -ForegroundColor Green }
function Warn($m){ Write-Host "!! $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# ---------- args (accept -Key=val and -Key val) ----------
$Provider = $null; $ApiKey = $null; $NoLaunch = $false
for ($i=0; $i -lt $args.Count; $i++) {
    $a = $args[$i]
    switch -Regex ($a) {
        '^-?Provider=(.+)$' { $Provider = $matches[1] }
        '^-?ApiKey=(.+)$'   { $ApiKey   = $matches[1] }
        '^-?NoLaunch$'      { $NoLaunch = $true }
        '^-?Provider$'      { $Provider = $args[++$i] }
        '^-?ApiKey$'        { $ApiKey   = $args[++$i] }
        default { Err "unknown argument: $a" }
    }
}

# ---------- region -> provider ----------
if (-not $Provider) {
    $tz = (Get-TimeZone -ErrorAction SilentlyContinue).Id
    $lang = $env:LANG, $env:LC_ALL -join ''
    if ($tz -match 'China|Shanghai|Urumqi' -or $lang -match 'zh_CN|zh_SG') { $Provider = 'bailian' }
    else { $Provider = 'bailian-intl' }
}
$CompatBlock = ''
switch ($Provider) {
    'bailian'      { $ProviderId='bailian';      $BaseUrl='https://dashscope.aliyuncs.com/apps/anthropic';     $Model='deepseek-v4-flash-0731'; $Api='anthropic'; $PName='Alibaba Cloud Bailian (China)'; $PSite='https://bailian.console.aliyun.com/' }
    'bailian-intl' { $ProviderId='bailian-intl'; $BaseUrl='https://dashscope-intl.aliyuncs.com/apps/anthropic'; $Model='deepseek-v4-flash';        $Api='anthropic'; $PName='Alibaba Cloud Model Studio (international)'; $PSite='https://dashscope-intl.console.aliyun.com/' }
    'deepseek'     { $ProviderId='deepseek';     $BaseUrl='https://api.deepseek.com/anthropic';                $Model='deepseek-v4-flash';        $Api='anthropic'; $PName='DeepSeek'; $PSite='https://platform.deepseek.com/' }
    'openrouter'   { $ProviderId='openrouter';   $BaseUrl='https://openrouter.ai/api/v1';                      $Model='deepseek/deepseek-v4-flash'; $Api='openai-completions'; $PName='OpenRouter'; $PSite='https://openrouter.ai/';
                     $CompatBlock = "      compat:`n        supportsDeveloperRole: false`n        maxTokensField: max_tokens" }
    default { Err "unknown provider: $Provider" }
}
Note "Provider: $ProviderId | Base: $BaseUrl | Model: $Model | API: $Api"
if (-not $ApiKey) { $ApiKey = 'PASTE-YOUR-API-KEY-HERE' }

# ---------- paths ----------
$WS   = Join-Path $env:USERPROFILE 'ai-workspace'
$DSH  = Join-Path $WS '.dsh'
$TMP  = Join-Path $env:TEMP ("dsh-templates-" + [guid]::NewGuid().ToString('N'))

function Refresh-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }

# ---------- fetch templates ----------
function Get-Templates {
    New-Item -ItemType Directory -Force -Path (Join-Path $TMP 'workspace'), (Join-Path $TMP 'dsh-home') | Out-Null
    foreach ($f in 'AGENTS.md','README.md','.gitignore','NEXT-STEPS.md','start-dsh.sh','start-dsh.cmd','start-dsh.ps1') {
        Invoke-WebRequest "$REPO_RAW/templates/workspace/$f" -OutFile (Join-Path $TMP "workspace\$f")
    }
    foreach ($f in 'settings.yaml','cordis.patch.yml','crawl4ai-row.yml','secrets.env','.gitignore') {
        Invoke-WebRequest "$REPO_RAW/templates/dsh-home/$f" -OutFile (Join-Path $TMP "dsh-home\$f")
    }
}

# ---------- stage?: render helpers ----------
function Write-IfAbsent([string]$srcPath, [string]$dstPath) {
    if (Test-Path $dstPath) { return $false }
    $dir = Split-Path $dstPath -Parent
    if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Copy-Item $srcPath $dstPath
    return $true
}

# ---------- Node ----------
function Ensure-Node {
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $v = (node -v) -replace '^v',''
        $maj = [int]($v.Split('.')[0]); $min = [int]($v.Split('.')[1])
        if ($maj -ge 24 -or ($maj -eq 22 -and $min -ge 19)) {
            Note "Node $v present (>=22.19 required)"; return
        }
        Warn "Node $v too old (need 22.19+ or 24+); installing LTS"
    }
    Note 'Installing Node.js LTS via winget'
    winget install --id OpenJS.NodeJS.LTS -e --accept-package-agreements --accept-source-agreements
    Refresh-Path
}

# ---------- dsh ----------
function Ensure-Dsh {
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Err 'npm not available after Node install; restart the terminal and re-run.' }
    Note "Installing dsh CLI: npm install -g $DSH_NPM_PKG"
    npm install -g $DSH_NPM_PKG
}

# ---------- seed ----------
function Seed-Workspace {
    if (-not (Test-Path $WS)) { New-Item -ItemType Directory -Force -Path $WS | Out-Null; Note "created $WS" }
    foreach ($f in 'README.md','.gitignore','AGENTS.md','start-dsh.cmd','start-dsh.ps1') {
        if (Write-IfAbsent (Join-Path $TMP "workspace\$f") (Join-Path $WS $f)) { Note "seeded $WS\$f" }
    }
    # NEXT-STEPS.md (rendered)
    $steps = Join-Path $WS 'NEXT-STEPS.md'
    if (-not (Test-Path $steps)) {
        $c = (Get-Content -Raw (Join-Path $TMP 'workspace\NEXT-STEPS.md'))
        $c = $c.Replace('{{PROVIDER_NAME}}',$PName).Replace('{{PROVIDER_SITE}}',$PSite)
        Set-Content -Path $steps -Value $c -Encoding UTF8
        Note "wrote $steps"
    }
}

function Seed-DshHome {
    New-Item -ItemType Directory -Force -Path $DSH | Out-Null
    # settings.yaml (rendered)
    $s = Join-Path $DSH 'settings.yaml'
    if (-not (Test-Path $s)) {
        $c = (Get-Content -Raw (Join-Path $TMP 'dsh-home\settings.yaml'))
        $c = $c.Replace('{{PROVIDER_ID}}',$ProviderId).Replace('{{PROVIDER_BASE_URL}}',$BaseUrl)
              .Replace('{{PROVIDER_MODEL}}',$Model).Replace('{{PROVIDER_API}}',$Api)
              .Replace('{{COMPAT_BLOCK}}',$CompatBlock)
        Set-Content -Path $s -Value $c -Encoding UTF8
        Note "wrote $s"
    }
    # secrets.env (rendered, secret — launchers source it before dsh boots)
    $e = Join-Path $DSH 'secrets.env'
    if (-not (Test-Path $e)) {
        $c = (Get-Content -Raw (Join-Path $TMP 'dsh-home\secrets.env')).Replace('{{DSH_API_KEY}}',$ApiKey)
        Set-Content -Path $e -Value $c -Encoding UTF8 -NoNewline
        Note "wrote $e (API key env)"
    }
    # cordis.patch.yml — full template, or append the aliased row if present without it
    $p = Join-Path $DSH 'cordis.patch.yml'
    if (-not (Test-Path $p)) {
        Copy-Item (Join-Path $TMP 'dsh-home\cordis.patch.yml') $p
        Note "enabled crawl4ai MCP in $p"
    } elseif (-not (Select-String -Path $p -SimpleMatch 'mcp-crawl4ai' -Quiet)) {
        Add-Content -Path $p -Value (Get-Content -Raw (Join-Path $TMP 'dsh-home\crawl4ai-row.yml'))
        Note "appended crawl4ai MCP row to $p"
    } else { Note "crawl4ai MCP already enabled in $p" }
    # inner .gitignore
    if (Write-IfAbsent (Join-Path $TMP 'dsh-home\.gitignore') (Join-Path $DSH '.gitignore')) { Note "wrote $DSH\.gitignore" }
}

# ---------- run ----------
Note 'Fetching installer templates'
Get-Templates

Note 'Installing Node.js (LTS) if needed'
Ensure-Node

Note 'Installing dsh CLI'
Ensure-Dsh

Note 'Creating the AI workspace'
Seed-Workspace

Note 'Seeding the DeepSeek Harness home'
Seed-DshHome

$env:DSH_HOME = $DSH
Remove-Item -Recurse -Force $TMP -ErrorAction SilentlyContinue

Note 'Done.'
Write-Host @'

  Almost ready! One step left: add your API key (unless you passed -ApiKey).
  See  ~\ai-workspace\NEXT-STEPS.md  — where to get a key and how to paste it
  into  ~\ai-workspace\.dsh\secrets.env  (or use Settings -> Models in the Web UI).

  Then start the assistant: double-click  start-dsh.cmd  in the workspace.
  The browser opens  http://127.0.0.1:3080  and crawl4ai MCP is ready.
'@
if ($env:BOOTSTRAP_NO_LAUNCH -eq '1') { Note 'skipping launch (BOOTSTRAP_NO_LAUNCH=1)' }
elseif (-not $NoLaunch) {
    Note 'launching DeepSeek Harness'
    Start-Process powershell -ArgumentList "Set-Location '$WS'; & '$WS\start-dsh.ps1'" -WindowStyle Hidden
}