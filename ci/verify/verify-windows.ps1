# verify-windows.ps1 — run INSIDE the Windows VM after the installer.
# Env: $env:TEST_PROVIDER, $env:TEST_API_KEY
$ErrorActionPreference = 'Continue'
$pass=0; $fail=0
function Ok($m){ Write-Host "  PASS  $m" -ForegroundColor Green; $script:pass++ }
function No($m){ Write-Host "  FAIL  $m" -ForegroundColor Red;   $script:fail++ }
function Have($c){ if(Get-Command $c -ErrorAction SilentlyContinue){Ok "$c on PATH"}else{No "$c on PATH"} }

Have code
Have git

if (code --list-extensions 2>$null | Select-String -Quiet 'anthropic.claude-code') {
    Ok 'claude-code extension installed'
} else { No 'claude-code extension installed' }

$ws = Join-Path $env:USERPROFILE 'ai-workspace'
$s = Join-Path $ws '.claude\settings.local.json'
if ((Test-Path $s) -and (Select-String -Path $s -Quiet 'ANTHROPIC_BASE_URL') -and (Select-String -Path $s -Quiet 'ANTHROPIC_AUTH_TOKEN') -and (Select-String -Path $s -Quiet 'ANTHROPIC_MODEL')) {
    Ok 'settings.local.json env block present'
} else { No 'settings.local.json env block' }

$m = Join-Path $ws '.mcp.json'
if ((Test-Path $m) -and (Select-String -Path $m -Quiet 'crawl4ai')) { Ok '.mcp.json crawl4ai entry' } else { No '.mcp.json crawl4ai' }

$venvPy = Join-Path $env:USERPROFILE '.bootstrap\crawl4ai-mcp-server\venv\Scripts\python.exe'
if ((Test-Path $venvPy) -and (& $venvPy -c 'import crawl4ai' 2>$null)) { Ok 'crawl4ai importable in venv' } else { No 'crawl4ai importable in venv' }

$ws = Join-Path $env:USERPROFILE 'ai-workspace'
if ((Test-Path $ws) -and (Test-Path (Join-Path $ws 'README.md'))) { Ok 'ai-workspace created' } else { No 'ai-workspace' }

if (Test-Path (Join-Path $ws 'NEXT-STEPS.md')) { Ok 'NEXT-STEPS.md present' } else { No 'NEXT-STEPS.md' }

if (Test-Path (Join-Path $ws 'CLAUDE.md')) { Ok 'CLAUDE.md present' } else { No 'CLAUDE.md' }

$vsc = Join-Path $env:APPDATA 'Code\User\settings.json'
if ((Test-Path $vsc) -and (Select-String -Path $vsc -Quiet 'security.workspace.trust.enabled.*false') -and (Select-String -Path $vsc -Quiet 'claudeCode.initialPermissionMode.*acceptEdits')) {
    Ok 'VS Code user settings (trust off + Edit-automatically)'
} else { No 'VS Code user settings' }

if ($env:TEST_API_KEY) {
    switch ($env:TEST_PROVIDER) {
        'bailian'    { $url='https://dashscope.aliyuncs.com/apps/anthropic/v1/messages'; $model='deepseek-v4-flash-0731' }
        'deepseek'   { $url='https://api.deepseek.com/anthropic/v1/messages';            $model='deepseek-v4-flash' }
        'openrouter' { $url='https://openrouter.ai/api/v1/messages';                     $model='deepseek/deepseek-v4-flash' }
        default      { $url='https://api.deepseek.com/anthropic/v1/messages';            $model='deepseek-v4-flash' }
    }
    $body = @{ model=$model; max_tokens=32; messages=@(@{role='user'; content='say hi'}) } | ConvertTo-Json -Compress
    try {
        $resp = Invoke-RestMethod -Uri $url -Method Post -Headers @{Authorization="Bearer $env:TEST_API_KEY"; 'Content-Type'='application/json'} -Body $body -TimeoutSec 60
        if ($resp.type -eq 'message') { Ok 'model connectivity' } else { No "model connectivity ($($resp | ConvertTo-Json -Compress -Depth 5))" }
    } catch { No "model connectivity ($($_.Exception.Message))" }
} else {
    Write-Host '  SKIP  model connectivity (no TEST_API_KEY)'
}

Write-Host ''
Write-Host "RESULT: $pass passed, $fail failed"
exit $fail
