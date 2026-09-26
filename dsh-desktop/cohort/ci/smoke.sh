#!/usr/bin/env bash
# dsh-desktop/cohort/ci/smoke.sh — host-side smoke for the cohort feature.
#
# Does NOT need a VMware VM (the real prep.sh is already CI-tested by the
# existing ci/run-test.sh VM flow). This smoke focuses on what is NEW here:
#   1. inject_provider.py — replace AND insert paths, idempotency, byte-stable
#      outside the touched blocks.
#   2. generate.py — the page contains the (dummy) key and both commands.
#   3. cohort-prep.sh — the glue (key check, pristine backup, python pick,
#      inject invocation) against a temp harness with prep stubbed out.
#   3.5. cohort-setup.sh — the app-install glue: version pins agree across
#      sh/ps1/generate.py, missing key fails fast, app-detect + delegate to
#      cohort-prep (download branch only on a host without the app).
#   4. a real minimal chat call to Bailian with the content-inspection header,
#      proving key + endpoint + header actually work together.
#   5. (opt) the same call with the cohort main model.
#
# Secret handling: COHORT_CI_KEY is read from the gitignored root .env (never
# hardcoded, never committed). Generator output uses a dummy key and is deleted.
# All logs mask the key (first 4 … last 4).
#
# Run from a clone:
#   # put COHORT_CI_KEY=sk-… in .env (root, gitignored)
#   bash dsh-desktop/cohort/ci/smoke.sh

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
INJECT="$HERE/../inject_provider.py"
GENERATE="$HERE/../generate.py"
FIXTURE="$HERE/fixtures/settings.sample.yaml"

note()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
fail()  { printf '\033[1;31mFAIL:\033[0m %s\n' "$*" >&2; exit 1; }
mask()  { local k="$1"; if [ "${#k}" -gt 8 ]; then printf '%s…%s' "${k:0:4}" "${k: -4}"; else printf '…'; fi; }

# load the gitignored root .env if present (COHORT_CI_KEY, COHORT_CI_MODEL, …)
if [ -f "$REPO/.env" ]; then
  set -a; . "$REPO/.env"; set +a
fi

KEY="${COHORT_CI_KEY:-${TEST_API_KEY:-}}"
MODEL="${COHORT_CI_MODEL:-deepseek-v4-flash-0731}"
VERIFY_MAIN="${COHORT_CI_VERIFY_MAIN_MODEL:-0}"
[ -n "$KEY" ] || fail "COHORT_CI_KEY missing — set it in $REPO/.env (gitignored)."

note "cohort smoke starting (key masked: $(mask "$KEY"), model: $MODEL)"

PYBIN="python3"
command -v "$PYBIN" >/dev/null 2>&1 || PYBIN="$HOME/ai-workspace/.venv/bin/python"
command -v "$PYBIN" >/dev/null 2>&1 || fail "no python3 (and no workspace venv python)"
"$PYBIN" -c 'import yaml' >/dev/null 2>&1 || fail "pyyaml not available for $PYBIN"

TMP="$(mktemp -d /tmp/cohort-smoke.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# ----------------------------------------------------------------------------
# Step 1 — inject_provider.py: replace path (fixture has `training`) + insert
# path (training stripped) + idempotency.
# ----------------------------------------------------------------------------
note "Step 1: inject_provider.py unit tests"

# 1a. replace path on the fixture (inject writes <harness-home>/settings.yaml).
cp "$FIXTURE" "$TMP/settings.yaml"
"$PYBIN" "$INJECT" --harness-home "$TMP" --key "$KEY" --label "CI Cohort" >/dev/null
"$PYBIN" - "$TMP/settings.yaml" "$KEY" <<'PY' || fail "replace-path assertions failed"
import sys, yaml
path, key = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(path))
p = d['llm-pi-ai']['providers']['training']
assert p['api'] == 'openai-responses', p.get('api')
assert p['apiKeyEnv'] == 'TRAINING_API_KEY', p.get('apiKeyEnv')
assert p['baseURL'] == 'https://dashscope.aliyuncs.com/compatible-mode/v1', p.get('baseURL')
assert p['displayName'] == 'CI Cohort', p.get('displayName')
assert p['headers']['X-DashScope-DataInspection'] == '{"input":"disable","output":"disable"}', p.get('headers')
assert [m['id'] for m in p['models']] == ['deepseek-v4-flash-0731'], p.get('models')
# maku-bailian untouched (still there, header intact)
assert 'maku-bailian' in d['llm-pi-ai']['providers']
adm = d['agent-default-model']
assert adm['provider'] == 'training' and adm['model'] == 'deepseek-v4-flash-0731', adm
print('  replace-path OK')
PY

# 1b. idempotency: second run on the SAME file produces zero diff.
cp "$TMP/settings.yaml" "$TMP/s2.yaml"
"$PYBIN" "$INJECT" --harness-home "$TMP" --key "$KEY" --label "CI Cohort" >/dev/null
diff "$TMP/s2.yaml" "$TMP/settings.yaml" >/dev/null && echo "  idempotent OK" || fail "not idempotent (second run changed bytes)"

# 1c. insert path: strip the `training` block + agent-default-model, then inject.
"$PYBIN" - "$FIXTURE" "$TMP/insert.yaml" <<'PY' || fail "fixture strip failed"
import sys, yaml, re
src, dst = sys.argv[1], sys.argv[2]
lines = open(src).read().splitlines()
# drop the `    training:` block through the next 4-space sibling / top-level key.
out, i = [], 0
while i < len(lines):
    if re.match(r'^    training:\s*$', lines[i]):
        i += 1
        while i < len(lines) and not re.match(r'^(\S|    \S)', lines[i]):
            i += 1
        continue
    if re.match(r'^agent-default-model:\s*$', lines[i]):
        i += 1
        while i < len(lines) and not re.match(r'^\S', lines[i]):
            i += 1
        continue
    out.append(lines[i]); i += 1
open(dst, 'w').write('\n'.join(out) + '\n')
PY
mkdir -p "$TMP/insert-harness"
cp "$TMP/insert.yaml" "$TMP/insert-harness/settings.yaml"
"$PYBIN" "$INJECT" --harness-home "$TMP/insert-harness" --key "$KEY" --label "CI Cohort" >/dev/null
"$PYBIN" - "$TMP/insert-harness/settings.yaml" <<'PY' || fail "insert-path assertions failed"
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
p = d['llm-pi-ai']['providers']['training']
assert p['baseURL'] == 'https://dashscope.aliyuncs.com/compatible-mode/v1'
assert p['headers']['X-DashScope-DataInspection'] == '{"input":"disable","output":"disable"}'
assert d['agent-default-model'] == {'provider':'training','model':'deepseek-v4-flash-0731'}
# the maku-bailian provider that was already there is untouched
assert 'maku-bailian' in d['llm-pi-ai']['providers']
print('  insert-path OK')
PY

# 1d. credentials: version:1 first (0.9.x hard requirement) + key under refs.
"$PYBIN" - "$TMP/insert-harness/.credentials.yaml" "$KEY" <<'PY' || fail "credentials assertions failed"
import sys, yaml
path, key = sys.argv[1], sys.argv[2]
raw = open(path).read()
first = next(ln for ln in raw.splitlines() if ln.strip())
assert first == "version: 1", f"credentials file must start with 'version: 1' (got {first!r}) -- 0.9.x harness refuses to start otherwise"
d = yaml.safe_load(raw)
assert d['refs']['TRAINING_API_KEY'] == key, d.get('refs')
print('  credentials OK (version: 1 + refs nesting)')
PY

note "Step 1 passed"

# ----------------------------------------------------------------------------
# Step 2 — generate.py: the page contains both commands and the (dummy) key.
# ----------------------------------------------------------------------------
note "Step 2: generate.py unit test (dummy key)"
DUMMY="sk-ci-dummy-1234567890"
"$PYBIN" "$GENERATE" --id ci-smoke --label "CI Smoke Cohort" --key "$DUMMY" >/dev/null
PAGE="$HERE/../cohorts/ci-smoke.html"
[ -f "$PAGE" ] || fail "generator produced no page"
# the command is HTML-escaped (quotes -> &#x27;), so match the key value fixed.
grep -qF "TRAINING_API_KEY" "$PAGE" || fail "mac command missing key var in page"
grep -qF "$DUMMY" "$PAGE" || fail "page missing dummy key value"
grep -q "cohort-setup.sh" "$PAGE" && grep -q "cohort-setup.ps1" "$PAGE" || fail "page missing command URLs"
grep -q '{{' "$PAGE" && fail "unrendered template placeholder in page" || true
"$PYBIN" - "$PAGE" <<'PY' || fail "page not well-formed"
import sys, html.parser
class P(html.parser.HTMLParser):
    def __init__(self): super().__init__(); self.ok=True
    def error(self, m): self.ok=False
p=P(); p.feed(open(sys.argv[1]).read()); assert p.ok
print('  page well-formed, commands + key present')
PY
rm -f "$PAGE"
note "Step 2 passed"

# ----------------------------------------------------------------------------
# Step 3 — cohort-prep.sh glue (prep stubbed): key check, backup, python pick,
# insert into a real (temp) harness dir, then verify the written files.
# ----------------------------------------------------------------------------
note "Step 3: cohort-prep.sh e2e glue (prep stubbed, temp harness)"
WS="$TMP/ws"; HARN="$TMP/harness"
mkdir -p "$WS" "$HARN"
# pre-seed a minimal settings.yaml WITHOUT a training provider, so cohort-prep's
# pristine backup_once has a file to back up, and inject takes the insert path.
cat > "$HARN/settings.yaml" <<'YML'
ui-onboarding:
  welcomeNoticeVersion: 2026-08-13.1
llm-pi-ai:
  providers:
    personal:
      api: openai-responses
      apiKeyEnv: MY_OWN_KEY
      baseURL: https://example.com/v1
      displayName: My own
permission:
  defaultPreset: workspace-write
YML
# stub prep: create the artifact cohort-prep.sh requires (the workspace venv
# python) and do nothing else (the real prep is CI-tested by the VM flow). The
# fake python forwards to PYBIN, which Step 0 verified can import yaml.
mkdir -p "$WS/.venv/bin"
printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$PYBIN" > "$WS/.venv/bin/python"
chmod +x "$WS/.venv/bin/python"
STUB="$TMP/prep-stub.sh"
printf '#!/usr/bin/env bash\necho "(prep stubbed for cohort smoke)"\n' > "$STUB"
chmod +x "$STUB"

export DSH_HOME="$HARN" WORKSPACE_DIR="$WS"
export PREP_URL="$STUB" INJECT_URL="$INJECT"
# inline env (not export) for MODEL/BASE_URL/LABEL so Step 4's MODEL stays the
# COHORT_CI_MODEL smoke value, not the cohort main model.
DSH_HOME="$HARN" WORKSPACE_DIR="$WS" PREP_URL="$STUB" INJECT_URL="$INJECT" \
  TRAINING_API_KEY="$KEY" MODEL="deepseek-v4-flash-0731" \
  BASE_URL="https://dashscope.aliyuncs.com/compatible-mode/v1" LABEL="CI Cohort" \
  bash "$HERE/../cohort-prep.sh" >/dev/null
unset DSH_HOME WORKSPACE_DIR PREP_URL INJECT_URL

# pristine backup was taken before inject (cohort-prep's backup_once).
[ -f "$HARN/settings.yaml.dsh-bak" ] || fail "cohort-prep did not back up settings.yaml"
"$PYBIN" - "$HARN/settings.yaml" "$HARN/.credentials.yaml" "$KEY" <<'PY' || fail "e2e assertions failed"
import sys, yaml
s, c, key = sys.argv[1], sys.argv[2], sys.argv[3]
d = yaml.safe_load(open(s))
p = d['llm-pi-ai']['providers']['training']
assert p['apiKeyEnv'] == 'TRAINING_API_KEY' and p['baseURL'] == 'https://dashscope.aliyuncs.com/compatible-mode/v1'
assert p['headers']['X-DashScope-DataInspection'] == '{"input":"disable","output":"disable"}'
# the learner's pre-existing personal provider is untouched
assert 'personal' in d['llm-pi-ai']['providers'], 'personal provider clobbered'
assert d['agent-default-model'] == {'provider':'training','model':'deepseek-v4-flash-0731'}
# the pristine backup still holds the old (no training) state
b = yaml.safe_load(open(s + '.dsh-bak'))
assert 'training' not in b['llm-pi-ai']['providers'], 'backup is not pristine'
cr = yaml.safe_load(open(c))
assert cr['refs']['TRAINING_API_KEY'] == key
print('  e2e: provider + key + header + default-model + pristine backup OK')
PY
note "Step 3 passed"

# ----------------------------------------------------------------------------
# Step 3.5 — cohort-setup.sh glue: pin consistency, key guard, app-detect +
# delegate. Only the app-present branch is exercised (no ~176 MB download in
# CI); on a host without DSH Desktop.app that branch is skipped (same policy as
# dsh-desktop/ci/verify/verify-macos.sh tier 2). PowerShell syntax is not
# checked here (no pwsh on the mac host); cohort-setup.ps1 reuses the exact
# silent-install method proven by dsh-desktop/ci/install-windows.ps1 in the VM.
# ----------------------------------------------------------------------------
note "Step 3.5: cohort-setup.sh glue (pins, key guard, delegate)"
SETUP="$HERE/../cohort-setup.sh"
bash -n "$SETUP" || fail "cohort-setup.sh syntax error"

pin_sh="$(sed -n 's/^DSH_VERSION="\${DSH_VERSION:-\(v[0-9.]*\)}".*/\1/p' "$SETUP" | head -1)"
pin_ps="$(sed -n "s/.*else { '\(v[0-9.]*\)'.*/\1/p" "$HERE/../cohort-setup.ps1" | head -1)"
pin_gen="$("$PYBIN" -c "import re,sys;print(re.search(r'DSH_VERSION = \"(v[0-9.]+)\"', open(sys.argv[1]).read()).group(1))" "$HERE/../generate.py")"
[ -n "$pin_sh" ] && [ "$pin_sh" = "$pin_ps" ] && [ "$pin_sh" = "$pin_gen" ] \
  || fail "DSH Desktop version pin mismatch: sh=$pin_sh ps1=$pin_ps generate.py=$pin_gen"
echo "  version pin consistent across sh/ps1/generate.py: $pin_sh"

SETUP_PREP_STUB="$TMP/cohort-prep-stub.sh"
printf '#!/usr/bin/env bash\necho "(cohort-prep stubbed for setup smoke)"\n' > "$SETUP_PREP_STUB"
# missing key must fail fast (BEFORE any app download would start)
if env -u TRAINING_API_KEY COHORT_PREP_URL="$SETUP_PREP_STUB" bash "$SETUP" >/dev/null 2>&1; then
  fail "cohort-setup.sh ran without TRAINING_API_KEY"
fi
echo "  key guard OK (fails fast without TRAINING_API_KEY)"

if [ -d "/Applications/DSH Desktop.app" ] || [ -d "$HOME/Applications/DSH Desktop.app" ]; then
  out="$(COHORT_PREP_URL="$SETUP_PREP_STUB" TRAINING_API_KEY=dummy-key-smoke bash "$SETUP" 2>&1)"
  printf '%s' "$out" | grep -q "already installed" || fail "cohort-setup.sh did not detect the installed app"
  printf '%s' "$out" | grep -q "cohort-prep stubbed" || fail "cohort-setup.sh did not delegate to cohort-prep"
  echo "  app-detect + delegate to cohort-prep OK"
else
  echo "  SKIP app-detect branch (no DSH Desktop.app on this host)"
fi
note "Step 3.5 passed"

# ----------------------------------------------------------------------------
# Step 4 — real minimal Q&A: key + endpoint + content-inspection header.
# ----------------------------------------------------------------------------
note "Step 4: real minimal chat (model: $MODEL, header: X-DashScope-DataInspection disable)"
resp_file="$TMP/api.json"
http_code="$(curl -sS -o "$resp_file" -w '%{http_code}' \
  -X POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions \
  -H "Authorization: Bearer $KEY" \
  -H 'Content-Type: application/json' \
  -H 'X-DashScope-DataInspection: {"input":"disable","output":"disable"}' \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ping, reply OK\"}],\"max_tokens\":512}" || true)"
if [ "$http_code" != "200" ]; then
  # print the error body with any key redacted
  sed -E "s/$KEY/<redacted>/g" "$resp_file" >&2 || true
  fail "chat call failed (HTTP $http_code)"
fi
"$PYBIN" - "$resp_file" <<'PY' || fail "chat response assertion failed"
import sys, json
d = json.load(open(sys.argv[1]))
msg = d['choices'][0]['message']
# deepseek-v4-flash-0731 is a reasoning model: it may put tokens in
# reasoning_content and answer in content. Either way, a 200 with a non-empty
# message field proves key + endpoint + header all work.
content = msg.get('content') or ''
reasoning = msg.get('reasoning_content') or ''
assert content or reasoning, repr(msg)
print(f"  chat OK — content={content!r} reasoning={reasoning[:60]!r}")
PY
note "Step 4 passed"

# ----------------------------------------------------------------------------
# Step 5 — (opt) the cohort main model.
# ----------------------------------------------------------------------------
if [ "$VERIFY_MAIN" = "1" ]; then
  MAIN="deepseek-v4-flash-0731"
  note "Step 5 (opt): real chat with the main cohort model ($MAIN)"
  rf="$TMP/api-main.json"
  hc="$(curl -sS -o "$rf" -w '%{http_code}' \
    -X POST https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions \
    -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' \
    -H 'X-DashScope-DataInspection: {"input":"disable","output":"disable"}' \
    -d "{\"model\":\"$MAIN\",\"messages\":[{\"role\":\"user\",\"content\":\"ping, reply OK\"}],\"max_tokens\":512}" || true)"
  [ "$hc" = "200" ] || { sed -E "s/$KEY/<redacted>/g" "$rf" >&2 || true; fail "main-model call failed (HTTP $hc)"; }
  "$PYBIN" - "$rf" <<'PY' || fail "main-model response assertion failed"
import sys, json
d = json.load(open(sys.argv[1]))
msg = d['choices'][0]['message']
c = msg.get('content') or msg.get('reasoning_content') or ''
assert c, repr(msg)
print(f"  main-model OK — replied: {c[:80]!r}")
PY
  note "Step 5 passed"
fi

note "all cohort smoke checks passed ✓"
