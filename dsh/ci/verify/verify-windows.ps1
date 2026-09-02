# verify-windows.ps1 — run on the Windows VM after dsh/install.ps1.
# Asserts the DeepSeek Harness environment. Exits non-zero on any failure.
# Env: TEST_PROVIDER, TEST_API_KEY
$ErrorActionPreference = 'Continue'
$pass = 0; $fail = 0
function OK($m){ Write-Host "  PASS  $m"; $script:pass++ }
function NO($m){ Write-Host "  FAIL  $m"; $script:fail++ }

# The installer puts Node in %LOCALAPPDATA%\nodejs and uv in ~\.local\bin; the
# verify session is a fresh shell, so prepend both to PATH.
$env:Path = "$env:LOCALAPPDATA\nodejs;" + $env:USERPROFILE + '\.local\bin;' + $env:Path

$WS = Join-Path $env:USERPROFILE 'ai-workspace'
$DSH = Join-Path $WS '.dsh'

if (Get-Command node -ErrorAction SilentlyContinue) {
    $v = (node -v) -replace '^v',''; $maj=[int]($v.Split('.')[0]); $min=[int]($v.Split('.')[1])
    if ($maj -ge 24 -or ($maj -eq 22 -and $min -ge 19)) { OK "node $v (engine ok)" } else { NO "node $v too old" }
} else { NO 'node not found' }
if (Get-Command dsh -ErrorAction SilentlyContinue) { OK 'dsh on PATH' } else { NO 'dsh on PATH' }

foreach ($f in 'README.md','AGENTS.md','NEXT-STEPS.md','start-dsh.cmd','start-dsh.ps1') {
    if (Test-Path (Join-Path $WS $f)) { OK "$f present" } else { NO "$f present" }
}
if (Get-Content (Join-Path $WS '.gitignore') -Raw -ErrorAction SilentlyContinue -match '\.dsh/') { OK '.gitignore ignores .dsh/' } else { NO '.gitignore ignores .dsh/' }

if (Test-Path (Join-Path $DSH 'settings.yaml')) {
    $s = Get-Content (Join-Path $DSH 'settings.yaml') -Raw
    switch ($env:TEST_PROVIDER) {
        'bailian'      { $wantUrl='https://dashscope.aliyuncs.com/apps/anthropic';     $wantModel='deepseek-v4-flash-0731' }
        'bailian-intl' { $wantUrl='https://dashscope-intl.aliyuncs.com/apps/anthropic'; $wantModel='deepseek-v4-flash' }
        'deepseek'     { $wantUrl='https://api.deepseek.com/anthropic';                $wantModel='deepseek-v4-flash' }
        'openrouter'   { $wantUrl='https://openrouter.ai/api/v1';                      $wantModel='deepseek/deepseek-v4-flash' }
        default { $wantUrl=''; $wantModel='' }
    }
    if ($s -match "baseURL: $wantUrl" -and $s -match "id: $wantModel") { OK "settings.yaml route ($env:TEST_PROVIDER)" } else { NO "settings.yaml route ($env:TEST_PROVIDER)" }
    if ($s -match '\{\{') { NO 'settings.yaml leftover placeholders' } else { OK 'settings.yaml no placeholders' }
} else { NO 'settings.yaml' }

$e = Join-Path $DSH 'secrets.env'
$ec = Get-Content $e -Raw -ErrorAction SilentlyContinue
if ($ec -match '(?m)^DSH_API_KEY=') { OK 'secrets.env DSH_API_KEY present' } else { NO 'secrets.env DSH_API_KEY present' }

$p = Join-Path $DSH 'cordis.patch.yml'
$pc = Get-Content $p -Raw -ErrorAction SilentlyContinue
if ($pc -match 'mcp-crawl4ai' -and $pc -match '@deepseek-ai/dsh-mcp-client' -and $pc -match 'transport: stdio') { OK 'cordis.patch.yml enables crawl4ai (official mcp-client)' } else { NO 'cordis.patch.yml enablement' }

# composed config dump shows the mcp row
if (Get-Command dsh -ErrorAction SilentlyContinue) {
    $env:DSH_HOME = $DSH
    $out = (dsh web --dump-config 2>$null | Out-String)
    if ($out -match 'mcp-crawl4ai') { OK 'dump-config shows mcp-crawl4ai' } else { NO 'dump-config shows mcp-crawl4ai' }
    Remove-Item Env:DSH_HOME -ErrorAction SilentlyContinue
}

# web UI boots on 127.0.0.1:3080
if (Get-Command dsh -ErrorAction SilentlyContinue) {
    # clear any stale dsh from the dump-config step first (EADDRINUSE on 3080)
    Get-Process | Where-Object { $_.ProcessName -match 'dsh|node' } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $env:DSH_HOME = $DSH
    # Launch through cmd.exe so dsh.cmd shim + redirection work; capture output.
    $bootlog = Join-Path $env:TEMP 'dsh-web-boot.log'
    $p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','dsh web --no-open > bootlog 2>&1' -WorkingDirectory $WS -RedirectStandardOutput $bootlog -RedirectStandardError "$bootlog.err" -WindowStyle Hidden -PassThru -ErrorAction SilentlyContinue
    $boot = $false
    for ($i=0; $i -lt 120; $i++) {
        # any HTTP response means the server is up (don't demand 2xx)
        $code = & curl.exe -s -m 2 -o NUL -w "%{http_code}" http://127.0.0.1:3080/ 2>$null
        if ($code -and $code -ne '000') { $boot = $true; break }
        Start-Sleep -Seconds 2
    }
    if ($boot) {
        OK 'dsh web serves http://127.0.0.1:3080'
    } elseif ((Get-Content $bootlog -Raw -ErrorAction SilentlyContinue) -match 'http://127.0.0.1:3080' -and (Get-Process -Id $p.Id -ErrorAction SilentlyContinue)) {
        OK 'dsh web booted (URL printed, server process up)'
    } else {
        NO 'dsh web serves http://127.0.0.1:3080'
    }
    Get-Process | Where-Object { $_.ProcessName -match 'dsh|node' } | Stop-Process -Force -ErrorAction SilentlyContinue
}

if ($env:TEST_API_KEY) {
    switch ($env:TEST_PROVIDER) {
        'bailian'      { $url='https://dashscope.aliyuncs.com/apps/anthropic/v1/messages'; $model='deepseek-v4-flash-0731' }
        'bailian-intl' { $url='https://dashscope-intl.aliyuncs.com/apps/anthropic/v1/messages'; $model='deepseek-v4-flash' }
        'deepseek'     { $url='https://api.deepseek.com/anthropic/v1/messages'; $model='deepseek-v4-flash' }
        'openrouter'   { $url='https://openrouter.ai/api/v1/messages'; $model='deepseek/deepseek-v4-flash' }
        default        { $url='https://dashscope.aliyuncs.com/apps/anthropic/v1/messages'; $model='deepseek-v4-flash-0731' }
    }
    $body = '{"model":"' + $model + '","max_tokens":32,"messages":[{"role":"user","content":"say hi"}]}'
    # Pass the JSON via a temp file: PowerShell mangles embedded quotes when
    # curl.exe receives -d as a native argument (the API rejected the body).
    $bfile = Join-Path $env:TEMP 'dsh-conn.json'
    Set-Content -Path $bfile -Value $body -Encoding ASCII -NoNewline
    $resp = ''
    for ($attempt=0; $attempt -lt 2; $attempt++) {
        $resp = curl.exe -s -m 120 -X POST $url -H 'Content-Type: application/json' -H "Authorization: Bearer $env:TEST_API_KEY" -d "@$bfile"
        if ($resp -match '"type":"message"') { break }
        Start-Sleep -Seconds 5
    }
    Remove-Item $bfile -Force -ErrorAction SilentlyContinue
    if ($resp -match '"type":"message"') { OK "model connectivity ($env:TEST_PROVIDER)" } else { NO "model connectivity ($env:TEST_PROVIDER): $($resp.Substring(0,[Math]::Min(220,$resp.Length)))" }
} else { Write-Host '  SKIP  model connectivity (no TEST_API_KEY)' }

Write-Host ''
Write-Host "RESULT: $pass passed, $fail failed"
exit $fail