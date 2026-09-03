#!/usr/bin/env bash
# dsh-desktop/ci/verify/verify-macos.sh — runs ON a macOS machine (the CI host).
# Two tiers:
#   1. prep.sh in isolation (temp workspace/harness) — seeds + patch shape.
#   2. If a DSH Desktop.app is installed, its OWN bundled harness must compose
#      the crawl4ai mcp-client patch (dump-config). Skips (not fails) when no
#      app is present. Uses a throwaway DSH_HOME — never touches real app data.
set -uo pipefail

pass=0; fail=0; skip=0
ok(){ printf '  PASS  %s\n' "$*"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n' "$*"; fail=$((fail+1)); }
sk(){ printf '  SKIP  %s\n' "$*"; skip=$((skip+1)); }

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"   # repo root
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ---------- tier 1: prep.sh in isolation ----------
# UV_DIR gets a stub uvx so the script's uv step short-circuits and the patch
# carries an absolute path; the stub is never executed (composition only).
STUB="${T}/bin/uvx"
mkdir -p "$(dirname "$STUB")" && printf '#!/bin/sh\nexit 0\n' > "$STUB" && chmod +x "$STUB"

out="$(WORKSPACE_DIR="$T/ws" DSH_HOME="$T/harness" UV_DIR="${T}/bin" \
  bash "$ROOT/dsh-desktop/prep.sh" 2>&1 || true)"

# seeds present
seed_missing=""
for f in AGENTS.md README.md .gitignore NEXT-STEPS.md; do
  [ -f "$T/ws/$f" ] || seed_missing="$seed_missing $f"
done
[ -z "$seed_missing" ] && ok 'prep seeds ~/ai-workspace (AGENTS/README/.gitignore/NEXT-STEPS)' \
  || no "missing seeds:$seed_missing"

# no leftover placeholders
if grep -rq '{{' "$T/ws" "$T/harness/cordis.patch.yml" 2>/dev/null; then
  no 'no leftover {{ placeholders'
else
  ok 'no leftover placeholders'
fi

# patch shape: official mcp-client + pinned crawl4ai + absolute uvx
patch="$T/harness/cordis.patch.yml"
if grep -q 'mcp-crawl4ai' "$patch" \
   && grep -q "@deepseek-ai/dsh-mcp-client" "$patch" \
   && grep -q "crawl4ai-search-mcp==0.1.1" "$patch" \
   && grep -q "command: ${STUB}" "$patch"; then
  ok 'patch enables crawl4ai (official mcp-client, pinned, abs uvx)'
else
  no 'patch shape wrong — see below'; sed -n '1,20p' "$patch" | sed 's/^/    /'
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