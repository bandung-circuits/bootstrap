#!/usr/bin/env bash
# verify-linux.sh — run INSIDE the Linux VM after the installer.
# Asserts the environment is correctly set up. Exits non-zero on any failure.
# Env: TEST_PROVIDER (bailian|deepseek|openrouter), TEST_API_KEY
set -uo pipefail
pass=0; fail=0
ok(){ printf '  PASS  %s\n' "$*"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n' "$*"; fail=$((fail+1)); }
have(){ command -v "$1" >/dev/null 2>&1 && ok "$1 on PATH" || no "$1 on PATH"; }

have code
have python3

# VS Code Claude Code extension installed
if code --list-extensions 2>/dev/null | grep -qi 'anthropic.claude-code'; then
  ok 'claude-code extension installed'
else no 'claude-code extension installed'; fi

# settings.local.json env block (in the workspace, self-contained)
s="$HOME/ai-workspace/.claude/settings.local.json"
if [ -f "$s" ] && grep -q ANTHROPIC_BASE_URL "$s" && grep -q ANTHROPIC_AUTH_TOKEN "$s" && grep -q ANTHROPIC_MODEL "$s"; then
  ok 'settings.local.json env block present'
else no 'settings.local.json env block'; fi

# .mcp.json crawl4ai (workspace, self-contained) — uvx entry
m="$HOME/ai-workspace/.mcp.json"
if [ -f "$m" ] && grep -q '"crawl4ai-search-mcp==0.1.1"' "$m"; then
  ok '.mcp.json crawl4ai uvx entry'
else no '.mcp.json crawl4ai uvx entry'; fi

# uvx available (uvx ships with uv; installer runs PATH-agnostic via ~/.local/bin)
uvx_bin="$HOME/.local/bin/uvx"
command -v uvx >/dev/null 2>&1 && uvx_bin="$(command -v uvx)"
if [ -x "$uvx_bin" ]; then ok 'uvx available'; else no 'uvx available'; fi

# crawl4ai-search-mcp resolvable from PyPI (first uvx run builds the env)
if [ -x "$uvx_bin" ] && timeout 600 "$uvx_bin" --from crawl4ai-search-mcp==0.1.1 python -c 'import crawl4ai_mcp_server' >/dev/null 2>&1; then
  ok 'crawl4ai-search-mcp importable via uvx'
else no 'crawl4ai-search-mcp importable via uvx'; fi

# workspace created
if [ -d "$HOME/ai-workspace" ] && [ -f "$HOME/ai-workspace/README.md" ]; then
  ok 'ai-workspace created'
else no 'ai-workspace'; fi

# NEXT-STEPS.md onboarding file
if [ -f "$HOME/ai-workspace/NEXT-STEPS.md" ]; then ok 'NEXT-STEPS.md present'; else no 'NEXT-STEPS.md'; fi

# CLAUDE.md workspace rules
if [ -f "$HOME/ai-workspace/CLAUDE.md" ]; then ok 'CLAUDE.md present'; else no 'CLAUDE.md'; fi

# VS Code user settings: trust off, Claude Code sidebar + skip login, Copilot off
vsc="$HOME/.config/Code/User/settings.json"
if [ -f "$vsc" ] && grep -q '"security.workspace.trust.enabled": false' "$vsc" 2>/dev/null \
   && grep -q '"claudeCode.initialPermissionMode": "acceptEdits"' "$vsc" 2>/dev/null \
   && grep -q '"claudeCode.preferredLocation": "sidebar"' "$vsc" 2>/dev/null \
   && grep -q '"claudeCode.disableLoginPrompt": true' "$vsc" 2>/dev/null; then
  ok 'VS Code user settings (trust off + Claude Code sidebar + skip login)'
else no 'VS Code user settings'; fi

# The right sidebar must OPEN on first launch: the "hidden" defaultVisibility
# must NOT be present (its default "visibleInWorkspace" + seeded UI state
# shows the bar with Claude Code).
if [ -f "$vsc" ] && ! grep -q 'secondarySideBar.defaultVisibility' "$vsc" 2>/dev/null; then
  ok 'no secondarySideBar.defaultVisibility (right sidebar opens by default)'
else no 'secondarySideBar.defaultVisibility still set (would collapse the right sidebar)'; fi

# workspace .vscode/settings.json mirrors the Claude Code / Copilot settings
wvs="$HOME/ai-workspace/.vscode/settings.json"
if [ -f "$wvs" ] && grep -q 'claudeCode.preferredLocation' "$wvs" 2>/dev/null \
   && grep -q 'chat.commandCenter.enabled' "$wvs" 2>/dev/null; then
  ok 'workspace .vscode/settings.json seeded'
else no 'workspace .vscode/settings.json'; fi

# state.vscdb seeded: first-run onboarding suppressed + Claude docked in the
# right (secondary) sidebar and the bar marked non-empty (so it opens on
# first launch with Claude Code in it). One script, one grep line (pairing a
# heredoc body with a different command's grep breaks the check).
sdb="$HOME/.config/Code/User/globalStorage/state.vscdb"
if [ -f "$sdb" ] && python3 - "$sdb" <<'PY' 2>/dev/null | grep -q 'dock=yes.*bar=notempty'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
def get(k):
    r = c.execute('SELECT value FROM ItemTable WHERE key=?', (k,)).fetchone()
    return r[0] if r else None
onb = get('welcomeOnboarding.state')
pin = get('workbench.auxiliarybar.pinnedPanels')
emp = get('workbench.auxiliaryBar.empty')
flags = 'onboarding=' + (onb if onb else 'none')
flags += ' dock=' + ('yes' if pin and 'claude-sidebar-secondary' in pin else 'no')
flags += ' bar=' + ('notempty' if emp == 'false' else 'empty')
print(flags)
c.close()
PY
then ok 'VS Code UI-state seeded (onboarding + Claude docked, right sidebar opens)'
else no 'VS Code UI-state seeded'; fi

# The installer must NOT auto-open Claude Code anymore: the
# vscode://anthropic.claude-code/open URI opens a CENTER editor tab (the
# extension's primaryEditor.open), ignoring preferredLocation. Placement comes
# from the seeded UI state above instead. Docs/comments legitimately mention
# the URI, so match only the removed invocation patterns.
if grep -rnE 'Start-Process .*vscode://anthropic|opener.*claude-code/open' \
     "$HOME/bootstrap"/vscode/install.sh "$HOME/bootstrap"/vscode/install-wsl.sh "$HOME/bootstrap"/vscode/install.ps1 "$HOME/bootstrap"/vscode/lib 2>/dev/null; then
  no 'stale vscode://anthropic.claude-code/open auto-open in installer'
else ok 'no auto-open URI (Claude placed via seeded UI state)'; fi

# GitHub Copilot not installed as a marketplace extension (best-effort suppress)
if code --list-extensions 2>/dev/null | grep -qi 'github.copilot'; then
  no 'github.copilot still installed'
else ok 'github.copilot not installed (marketplace)'; fi

# model connectivity — actually call the backend. Prefer curl; fall back to
# python3 (a minimal VM may lack curl). No -4 (forcing IPv4 can break the VM
# route); retry once.
if [ -n "${TEST_API_KEY:-}" ]; then
  case "${TEST_PROVIDER:-deepseek}" in
    bailian)  url="https://dashscope.aliyuncs.com/apps/anthropic/v1/messages"; model="deepseek-v4-flash-0731" ;;
    bailian-intl) url="https://dashscope-intl.aliyuncs.com/apps/anthropic/v1/messages"; model="deepseek-v4-flash" ;;
    deepseek) url="https://api.deepseek.com/anthropic/v1/messages";            model="deepseek-v4-flash" ;;
    openrouter) url="https://openrouter.ai/api/v1/messages";                   model="deepseek/deepseek-v4-flash" ;;
    *) url="https://api.deepseek.com/anthropic/v1/messages"; model="deepseek-v4-flash" ;;
  esac
  body="{\"model\":\"$model\",\"max_tokens\":32,\"messages\":[{\"role\":\"user\",\"content\":\"say hi\"}]}"
  probe() {
    if command -v curl >/dev/null 2>&1; then
      curl -s -m 120 -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TEST_API_KEY" \
        -d "$body" 2>/dev/null || true
    elif command -v python3 >/dev/null 2>&1; then
      URL="$url" KEY="$TEST_API_KEY" BODY="$body" python3 -c '
import os,sys,urllib.request
req=urllib.request.Request(os.environ["URL"],data=os.environ["BODY"].encode())
req.add_header("Content-Type","application/json")
req.add_header("Authorization","Bearer "+os.environ["KEY"])
try:
    sys.stdout.write(urllib.request.urlopen(req,timeout=120).read().decode())
except Exception as e:
    sys.stdout.write("ERR %s"%e)'
    else
      printf ''
    fi
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
