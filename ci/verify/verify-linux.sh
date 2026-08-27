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
have git
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

# .mcp.json crawl4ai (workspace, self-contained)
m="$HOME/ai-workspace/.mcp.json"
if [ -f "$m" ] && grep -q crawl4ai "$m"; then ok '.mcp.json crawl4ai entry'; else no '.mcp.json crawl4ai'; fi

# crawl4ai venv importable
venvpy="$HOME/.bootstrap/crawl4ai-mcp-server/venv/bin/python"
if [ -x "$venvpy" ] && "$venvpy" -c 'import crawl4ai' 2>/dev/null; then
  ok 'crawl4ai importable in venv'
else no 'crawl4ai importable in venv'; fi

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

# workspace .vscode/settings.json mirrors the Claude Code / Copilot settings
wvs="$HOME/ai-workspace/.vscode/settings.json"
if [ -f "$wvs" ] && grep -q 'claudeCode.preferredLocation' "$wvs" 2>/dev/null \
   && grep -q 'chat.commandCenter.enabled' "$wvs" 2>/dev/null; then
  ok 'workspace .vscode/settings.json seeded'
else no 'workspace .vscode/settings.json'; fi

# state.vscdb seeded: first-run onboarding/theme picker suppressed
sdb="$HOME/.config/Code/User/globalStorage/state.vscdb"
if [ -f "$sdb" ] && python3 - "$sdb" <<'PY' 2>/dev/null | grep -q 'onboarding=true'
import sqlite3, sys
c = sqlite3.connect(sys.argv[1])
r = c.execute('SELECT value FROM ItemTable WHERE key="welcomeOnboarding.state"').fetchone()
c.close()
print('onboarding=' + (r[0] if r else 'none'))
PY
then ok 'VS Code UI-state seeded (onboarding suppressed)'
else no 'VS Code UI-state seeded'; fi

# GitHub Copilot not installed as a marketplace extension (best-effort suppress)
if code --list-extensions 2>/dev/null | grep -qi 'github.copilot'; then
  no 'github.copilot still installed'
else ok 'github.copilot not installed (marketplace)'; fi

# model connectivity — actually call the backend
if [ -n "${TEST_API_KEY:-}" ]; then
  case "${TEST_PROVIDER:-deepseek}" in
    bailian)  url="https://dashscope.aliyuncs.com/apps/anthropic/v1/messages"; model="deepseek-v4-flash-0731" ;;
    deepseek) url="https://api.deepseek.com/anthropic/v1/messages";            model="deepseek-v4-flash" ;;
    openrouter) url="https://openrouter.ai/api/v1/messages";                   model="deepseek/deepseek-v4-flash" ;;
    *) url="https://api.deepseek.com/anthropic/v1/messages"; model="deepseek-v4-flash" ;;
  esac
  resp=$(curl -s -m 60 -X POST "$url" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $TEST_API_KEY" \
    -d "{\"model\":\"$model\",\"max_tokens\":32,\"messages\":[{\"role\":\"user\",\"content\":\"say hi\"}]}" 2>/dev/null || true)
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
