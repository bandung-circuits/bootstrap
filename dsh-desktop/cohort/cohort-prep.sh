#!/usr/bin/env bash
# dsh-desktop/cohort/cohort-prep.sh — training-cohort one-command setup (macOS).
#
# Learner runs (the key is baked into the command on the cohort HTML page):
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh-desktop/cohort/cohort-prep.sh \
#     | TRAINING_API_KEY='sk-...' bash
#
# Prerequisite: DSH Desktop installed (https://dshdesktop.com/en/). macOS only
# here; Windows uses cohort-prep.ps1.
#
# This script REUSES the public dsh-desktop/prep.sh verbatim (it does NOT fork
# its logic) for everything the workspace needs — workspace seeds, uv, venv +
# crawl4ai, browser, the crawl4ai MCP registration, and the Full Access
# permission default. It then adds the two things prep.sh deliberately leaves to
# the learner, by calling inject_provider.py (the single source of truth):
#   - the Bailian `training` provider (baseURL + key + the content-inspection
#     header that https://extremeprogramming-cn.github.io/bailian-content-inspection/
#     documents) into settings.yaml + .credentials.yaml;
#   - `agent-default-model` pinned to the cohort model (deepseek-v4-flash-0731).
# After this, the learner only has to open the app and pick ~/ai-workspace.

set -euo pipefail

REPO_BASE="https://bandung-circuits.github.io/bootstrap"
PREP_URL="${PREP_URL:-${REPO_BASE}/dsh-desktop/prep.sh}"
INJECT_URL="${INJECT_URL:-${REPO_BASE}/dsh-desktop/cohort/inject_provider.py}"
MODEL="${MODEL:-deepseek-v4-flash-0731}"
BASE_URL="${BASE_URL:-https://dashscope.aliyuncs.com/compatible-mode/v1}"
LABEL="${LABEL:-Training}"
PROVIDER_ID="${PROVIDER_ID:-training}"

note() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# 0. key must be present (baked into the command on the cohort page).
: "${TRAINING_API_KEY:?TRAINING_API_KEY is missing — copy the command from your cohort page, not a generic one.}"

# 1. locate the DSH Desktop harness data dir (mirrors prep.sh's harness_discover).
harness_discover() {
  local cand
  for cand in \
    "${HOME}/Library/Application Support/dsh-desktop/harness" \
    "${HOME}/Library/Application Support/DSH Desktop/harness"; do
    [ -d "$cand" ] && { printf '%s\n' "$cand"; return 0; }
  done
  printf '%s\n' "${HOME}/Library/Application Support/dsh-desktop/harness"
}
HARNESS_HOME="${DSH_HOME:-$(harness_discover)}"

# 2. pristine backup of the two files we will touch, BEFORE prep runs (prep.sh
# itself edits settings.yaml for the permission default). Keep the first-ever
# backup so re-runs don't lose the original. inject_provider.py will see the
# .dsh-bak files exist and skip its own backup.
backup_once() {
  local f bak
  for f in "${HARNESS_HOME}/settings.yaml" "${HARNESS_HOME}/.credentials.yaml"; do
    [ -f "$f" ] || continue
    bak="${f}.dsh-bak"
    [ -f "$bak" ] && continue
    mkdir -p "${HARNESS_HOME}"
    cp -p "$f" "$bak"
    note "backed up $f -> $bak"
  done
}
backup_once

# 3. run the public prep (workspace, venv, crawl4ai MCP, Full Access). REUSE —
# do not duplicate. PREP_URL may be a local path (CI) or a URL (learner).
note "Running the standard workspace prep"
if [ -f "$PREP_URL" ]; then
  bash "$PREP_URL"
else
  curl -fsSL "$PREP_URL" | bash
fi

# 4. Use the workspace venv's python by ABSOLUTE PATH. prep just created it;
# the dsh-desktop design is fully self-contained in ~/ai-workspace (no PATH
# lookup, no system python).
PY="${WORKSPACE_DIR:-$HOME/ai-workspace}/.venv/bin/python"
[ -x "$PY" ] || err "workspace venv python not found at $PY -- prep did not complete. Re-run the command from your cohort page."

# 5. run the provider/key/header/default-model injection (single source of truth).
note "Configuring the training provider, key, and default model"
_INJECT_TMP=""
run_inject() {
  if [ -f "$INJECT_URL" ]; then
    "$PY" "$INJECT_URL" "$@"
  else
    _INJECT_TMP="$(mktemp /tmp/cohort-inject.XXXXXX.py)"
    curl -fsSL "$INJECT_URL" -o "$_INJECT_TMP"
    "$PY" "$_INJECT_TMP" "$@"
  fi
}
cleanup() { [ -n "$_INJECT_TMP" ] && rm -f "$_INJECT_TMP"; return 0; }
trap cleanup EXIT

run_inject \
  --harness-home "$HARNESS_HOME" \
  --key "$TRAINING_API_KEY" \
  --base-url "$BASE_URL" \
  --model "$MODEL" \
  --label "$LABEL" \
  --provider-id "$PROVIDER_ID" \
  --workspace "${WORKSPACE_DIR:-$HOME/ai-workspace}"

note "Done."

cat <<NEXT

  Your AI workspace is ready at  ~/ai-workspace  — everything is set up:

    Model:            $MODEL  (via $PROVIDER_ID provider, Bailian)
    API key:          already configured — you do NOT paste anything in the app
    Content safety:   platform-side inspection header set to avoid false blocks
    Permission:       Full Access (the agent can work without prompting you)
    crawl4ai MCP:     enabled (web fetch + search, free, no key)

  Last step (one click in the app):
    1. Open DSH Desktop.
    2. Choose workspace ->  ~/ai-workspace
    3. Start asking. The model is already selected.

  Note: this key is shared by everyone in your cohort and expires after the
  training. Keep it on the page you were given; do not post it publicly.
NEXT
