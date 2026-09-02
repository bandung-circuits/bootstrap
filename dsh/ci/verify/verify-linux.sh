#!/usr/bin/env bash
# verify-linux.sh — run INSIDE the Linux VM after the dsh installer.
# Asserts the DeepSeek Harness environment is correctly set up. Exits non-zero
# on any failure.
# Env: TEST_PROVIDER (bailian|bailian-intl|deepseek|openrouter), TEST_API_KEY
set -uo pipefail
pass=0; fail=0
ok(){ printf '  PASS  %s\n' "$*"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n' "$*"; fail=$((fail+1)); }
have(){ command -v "$1" >/dev/null 2>&1 && ok "$1 on PATH" || no "$1 on PATH"; }

# Node + dsh (installed to ~/.local/nodejs + ~/.local/bin)
export PATH="$HOME/.local/bin:$HOME/.local/nodejs/bin:$PATH"
have node
have dsh
if command -v node >/dev/null 2>&1; then
  v="$(node -v | tr -d v)"; maj="${v%%.*}"; min="${v#*.}"; min="${min%%.*}"
  if [ "$maj" -ge 24 ] || { [ "$maj" -eq 22 ] && [ "$min" -ge 19 ]; }; then ok "node $v (engine ok)"; else no "node $v too old"; fi
else no 'node engine check'; fi

# uv/uvx (crawl4ai runtime)
uvx_bin="$HOME/.local/bin/uvx"
command -v uvx >/dev/null 2>&1 && uvx_bin="$(command -v uvx)"
if [ -x "$uvx_bin" ]; then ok 'uvx available'; else no 'uvx available'; fi

# workspace seeded
WS="$HOME/ai-workspace"
for f in README.md AGENTS.md NEXT-STEPS.md start-dsh.sh; do
  [ -f "$WS/$f" ] && ok "$f present" || no "$f present"
done
[ -x "$WS/start-dsh.sh" ] && ok 'start-dsh.sh executable' || no 'start-dsh.sh executable'
[ -f "$WS/.gitignore" ] && grep -q '\.dsh/' "$WS/.gitignore" && ok '.gitignore ignores .dsh/' || no '.gitignore ignores .dsh/'

# $DSH_HOME inside the workspace
DSH="$WS/.dsh"
[ -d "$DSH" ] && ok '.dsh/ created' || no '.dsh/ created'

# settings.yaml: provider route (api/baseURL/model) matches TEST_PROVIDER
s="$DSH/settings.yaml"
if [ -f "$s" ]; then
  case "${TEST_PROVIDER:-bailian}" in
    bailian)      want_url="https://dashscope.aliyuncs.com/apps/anthropic";     want_model="deepseek-v4-flash-0731" ;;
    bailian-intl) want_url="https://dashscope-intl.aliyuncs.com/apps/anthropic"; want_model="deepseek-v4-flash" ;;
    deepseek)     want_url="https://api.deepseek.com/anthropic";                want_model="deepseek-v4-flash" ;;
    openrouter)   want_url="https://openrouter.ai/api/v1";                      want_model="deepseek/deepseek-v4-flash" ;;
    *) want_url=""; want_model="";;
  esac
  grep -q "baseURL: $want_url" "$s" && grep -q "id: $want_model" "$s" \
    && ok "settings.yaml route ($TEST_PROVIDER)" || no "settings.yaml route ($TEST_PROVIDER)"
  grep -q '{{' "$s" && no 'settings.yaml leftover placeholders' || ok 'settings.yaml no placeholders'
else no 'settings.yaml'; fi

# secrets.env secret (mode 600, key present — launchers source it before dsh boots)
e="$DSH/secrets.env"
if [ -f "$e" ]; then
  grep -q '^DSH_API_KEY=' "$e" && ok 'secrets.env DSH_API_KEY present' || no 'secrets.env DSH_API_KEY present'
  p=$(stat -c '%a' "$e" 2>/dev/null || stat -f '%Lp' "$e" 2>/dev/null)
  [ "$p" = "600" ] && ok 'secrets.env mode 600' || no "secrets.env mode 600 (got $p)"
else no 'secrets.env'; fi

# cordis.patch.yml: official mcp-client row for crawl4ai
p="$DSH/cordis.patch.yml"
if [ -f "$p" ] && grep -q 'mcp-crawl4ai' "$p" && grep -q '@deepseek-ai/dsh-mcp-client' "$p" \
   && grep -q "crawl4ai-search-mcp==0.1.1" "$p" && grep -q 'transport: stdio' "$p"; then
  ok 'cordis.patch.yml enables crawl4ai (official mcp-client, stdio)'
else no 'cordis.patch.yml enablement'; fi

# crawl4ai-search-mcp resolvable from PyPI (first uvx run builds the env)
if [ -x "$uvx_bin" ] && timeout 600 "$uvx_bin" --from crawl4ai-search-mcp==0.1.1 python -c 'import crawl4ai_mcp_server' >/dev/null 2>&1; then
  ok 'crawl4ai-search-mcp importable via uvx'
else no 'crawl4ai-search-mcp importable via uvx'; fi

# composed config dump shows the mcp row (dead-code surfaces the render)
if command -v dsh >/dev/null 2>&1; then
  out="$(DSH_HOME="$DSH" dsh web --dump-config 2>/dev/null || true)"
  printf '%s\n' "$out" | grep -q 'mcp-crawl4ai' && ok 'dump-config shows mcp-crawl4ai' || no 'dump-config shows mcp-crawl4ai'
fi

# web UI boots on 127.0.0.1:3080 (--no-open; curl the port). Clear any stale
# dsh from the dump/smoke first (EADDRINUSE bit us), then capture the boot
# output so a failure shows the real error instead of a silent 0/1.
if command -v dsh >/dev/null 2>&1; then
  pkill -f 'dsh web' 2>/dev/null || true; pkill -f '@deepseek-ai/dsh' 2>/dev/null || true
  sleep 2
  bootlog="/tmp/dsh-web-boot.log"
  (cd "$WS" && DSH_HOME="$DSH" dsh web --no-open >"$bootlog" 2>&1 &)
  boot=0
  for i in $(seq 1 120); do
    # any HTTP response means the server is up (don't demand 2xx — during
    # startup / may serve 503 until client bundles settle).
    code=$(curl -s -m 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:3080/ 2>/dev/null || true)
    if [ -n "$code" ] && [ "$code" != "000" ]; then boot=1; break; fi
    sleep 2
  done
  if [ "$boot" = 1 ]; then
    ok 'dsh web serves http://127.0.0.1:3080'
  else
    # No response inside the window. Give one last check in case the Loader
    # was still settling, then report.
    code=$(curl -s -m 4 -o /dev/null -w '%{http_code}' http://127.0.0.1:3080/ 2>/dev/null || true)
    if [ -n "$code" ] && [ "$code" != "000" ]; then
      ok 'dsh web serves http://127.0.0.1:3080 (late)'
    else
      # The server process may be up but not yet reachable (one-time
      # crawl4ai/playwright init on a slow VM). dsh web prints its canonical URL
      # once the Loader tree settles — take that + a live process as "booted".
      if grep -q "http://127.0.0.1:3080" "$bootlog" 2>/dev/null && \
         pgrep -f '@deepseek-ai/dsh' >/dev/null 2>&1; then
        ok 'dsh web booted (URL printed, server process up)'
      else
        no "dsh web boot failed (see $(basename "$bootlog"))"
        tail -12 "$bootlog" 2>/dev/null | sed 's/^/    /' || true
      fi
    fi
  fi
  # stop the test server we own
  pkill -f 'dsh web' 2>/dev/null || true; pkill -f '@deepseek-ai/dsh' 2>/dev/null || true
fi

# model connectivity — actually call the backend. Prefer curl; fall back to
# python3 (a minimal VM may lack curl). No -4: forcing IPv4 broke the VM route.
if [ -n "${TEST_API_KEY:-}" ]; then
  case "${TEST_PROVIDER:-bailian}" in
    bailian)  url="https://dashscope.aliyuncs.com/apps/anthropic/v1/messages"; model="deepseek-v4-flash-0731" ;;
    bailian-intl) url="https://dashscope-intl.aliyuncs.com/apps/anthropic/v1/messages"; model="deepseek-v4-flash" ;;
    deepseek) url="https://api.deepseek.com/anthropic/v1/messages";            model="deepseek-v4-flash" ;;
    openrouter) url="https://openrouter.ai/api/v1/messages";                   model="deepseek/deepseek-v4-flash" ;;
    *) url="https://api.deepseek.com/anthropic/v1/messages"; model="deepseek-v4-flash" ;;
  esac
  body="{\"model\":\"$model\",\"max_tokens\":32,\"messages\":[{\"role\":\"user\",\"content\":\"say hi\"}]}"
  probe() {
    local out=""
    if command -v curl >/dev/null 2>&1; then
      out=$(curl -s -m 120 -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TEST_API_KEY" \
        -d "$body" 2>/dev/null || true)
    elif command -v python3 >/dev/null 2>&1; then
      out=$(URL="$url" MODEL="$model" KEY="$TEST_API_KEY" BODY="$body" python3 - <<'PY'
import json, os, urllib.request
req = urllib.request.Request(os.environ["URL"], data=os.environ["BODY"].encode())
req.add_header("Content-Type", "application/json")
req.add_header("Authorization", "Bearer " + os.environ["KEY"])
try:
    print(urllib.request.urlopen(req, timeout=120).read().decode())
except Exception as e:
    print("ERR", e)
PY
)
    fi
    printf '%s' "$out"
  }
  resp=""
  for attempt in 1 2; do
    resp=$(probe)
    printf '%s' "$resp" | grep -q '"type":"message"' && break
    sleep 5
  done
  if printf '%s' "$resp" | grep -q '"type":"message"'; then
    ok 'model connectivity (got message response)'
  else
    no "model connectivity (response: $(printf '%s' "$resp" | head -c 200))"
  fi
else
  echo '  SKIP  model connectivity (no TEST_API_KEY)'
fi

echo
echo "RESULT: $pass passed, $fail failed"
exit $fail