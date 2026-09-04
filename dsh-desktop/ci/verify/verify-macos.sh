#!/usr/bin/env bash
# dsh-desktop/ci/verify/verify-macos.sh — runs ON a macOS machine (the CI host).
# Two tiers:
#   1. prep.sh end-to-end into a THROWAWAY workspace + harness: seeds, a real
#      venv with crawl4ai inside the workspace, and a patch that points the
#      official mcp-client at the workspace venv (no PATH dependence).
#   2. If a DSH Desktop.app is installed, its OWN bundled harness must compose
#      the crawl4ai mcp-client patch (dump-config). Skips (not fails) when no
#      app is present. Never touches real app data or ~/.crawl4ai.
set -uo pipefail

pass=0; fail=0; skip=0
ok(){ printf '  PASS  %s\n' "$*"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n' "$*"; fail=$((fail+1)); }
sk(){ printf '  SKIP  %s\n' "$*"; skip=$((skip+1)); }

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ---------- tier 1: prep.sh end-to-end (hidden browser dl for speed) ----------
out="$(WORKSPACE_DIR="$T/ws" DSH_HOME="$T/harness" PREP_NO_BROWSER=1 \
  bash "$ROOT/dsh-desktop/prep.sh" 2>&1 || true)"

seed_missing=""
for f in AGENTS.md README.md .gitignore NEXT-STEPS.md; do
  [ -f "$T/ws/$f" ] || seed_missing="$seed_missing $f"
done
[ -z "$seed_missing" ] && ok 'prep seeds ~/ai-workspace (AGENTS/README/.gitignore/NEXT-STEPS)' \
  || no "missing seeds:$seed_missing"

# no leftover placeholders in OUR files (seeds + patch only — scanning the
# whole workspace would false-positive on installed Python packages).
if grep -q '{{' \
    "$T/ws/AGENTS.md" "$T/ws/README.md" "$T/ws/.gitignore" "$T/ws/NEXT-STEPS.md" \
    "$T/harness/cordis.patch.yml" 2>/dev/null; then
  no 'no leftover {{ placeholders'
else
  ok 'no leftover placeholders'
fi

# python + crawl4ai live INSIDE the workspace venv (the point of self-containment)
venv_py="$T/ws/.venv/bin/python"
cr4_bin="$T/ws/.venv/bin/crawl4ai-search"
if [ -x "$venv_py" ] && "$venv_py" -c 'import crawl4ai_mcp_server' >/dev/null 2>&1; then
  ok 'venv python imports crawl4ai_mcp_server (in-workspace)'
else
  no 'workspace venv missing or crawl4ai_mcp_server not importable'
fi
if [ -x "$cr4_bin" ]; then ok "crawl4ai executable present ($cr4_bin)"; else no 'crawl4ai executable missing'; fi

# sitecustomize.py must redirect crawl4ai data/browser into the workspace for
# ANY venv python invocation (not just the MCP server).
sitecustomize="$("$venv_py" - <<'PY' 2>/dev/null
import site, os
print(os.path.join(site.getsitepackages()[0], 'sitecustomize.py'))
PY
)"
if [ -n "$sitecustomize" ] && [ -f "$sitecustomize" ] \
   && grep -q 'CRAWL4_AI_BASE_DIRECTORY' "$sitecustomize" \
   && grep -q 'PLAYWRIGHT_BROWSERS_PATH' "$sitecustomize"; then
  ok 'venv sitecustomize redirects crawl4ai data/browser to workspace'
else
  no 'venv sitecustomize missing or lacks workspace env'
fi

# default permission preset pinned to danger-full-access (Full Access)
settings="$T/harness/settings.yaml"
if [ -f "$settings" ] && grep -q 'defaultPreset: danger-full-access' "$settings"; then
  ok 'harness settings.yaml pins permission default to danger-full-access'
else
  no 'harness settings.yaml does not pin danger-full-access'
fi

patch="$T/harness/cordis.patch.yml"
if grep -q 'mcp-crawl4ai' "$patch" \
   && grep -q "@deepseek-ai/dsh-mcp-client" "$patch" \
   && grep -q "command: ${cr4_bin}" "$patch" \
   && grep -q "CRAWL4_AI_BASE_DIRECTORY: $T/ws" "$patch" \
   && grep -q "PLAYWRIGHT_BROWSERS_PATH: $T/ws/.browsers" "$patch" \
   && grep -q "PYTHONUTF8" "$patch"; then
  ok 'patch: official mcp-client -> workspace venv + in-workspace browsers/data + PYTHONUTF8'
else
  no 'patch shape wrong — see below'; sed -n '1,20p' "$patch" | sed 's/^/    /'
fi

# git (best-effort; the CI host usually has it)
if command -v git >/dev/null 2>&1; then
  ok "git present ($(git --version 2>/dev/null | head -c 40))"
else
  sk 'git not on this host (best-effort install skipped)'
fi

# ---------- tier 2: real bundled harness composes the patch ----------
BIN=""
for p in \
  "/Applications/DSH Desktop.app/Contents/Resources/app.asar.unpacked/node_modules/@deepseek-ai/dsh/lib/bin.js" \
  "/Applications/DSH Desktop.app/Contents/Resources/app/node_modules/@deepseek-ai/dsh/lib/bin.js"; do
  [ -f "$p" ] && { BIN="$p"; break; }
done
if [ -n "$BIN" ] && command -v node >/dev/null 2>&1; then
  out2="$(DSH_HOME="$T/harness" node "$BIN" web --dump-config 2>&1 || true)"
  if printf '%s' "$out2" | grep -q 'mcp-crawl4ai'; then
    ok 'bundled DSH harness composes mcp-crawl4ai (dump-config)'
  else
    no 'bundled harness did not compose mcp-crawl4ai'
  fi
else
  sk 'DSH Desktop.app not found on this host — bundled-compose tier skipped'
fi

echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
exit $fail