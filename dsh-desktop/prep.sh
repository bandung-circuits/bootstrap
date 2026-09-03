#!/usr/bin/env bash
# dsh-desktop/prep.sh — one-command workspace prep for DSH Desktop (macOS).
#
# Usage (macOS):
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh-desktop/prep.sh | bash
# or from a clone:
#   bash dsh-desktop/prep.sh
#
# Prerequisite: DSH Desktop installed (https://dshdesktop.com/en/). Platforms:
# macOS + Windows only (the app has no Linux build).
#
# Everything is installed INSIDE the workspace (~/ai-workspace) so the app's
# subprocesses can find it without touching ~/.local/bin (not on the app's
# PATH) or ~/.crawl4ai:
#   ~/ai-workspace/
#     AGENTS.md README.md .gitignore NEXT-STEPS.md   seeds
#     .venv/                        python + crawl4ai-search-mcp pre-installed
#     .browsers/                    Playwright Chromium (pre-downloaded)
#     .crawl4ai/                    crawl4ai data (CRAWL4_AI_BASE_DIRECTORY)
#     .local/bin/                   uv (a helper, not needed at runtime)
#
# The crawl4ai MCP server runs the workspace venv's crawl4ai-search executable
# by absolute path (no PATH lookup). Odds & ends: the app's harness data stays
# in the DSH Desktop app-data dir (macOS ~/Library/Application Support/DSH
# Desktop/harness); the model key is entered by the learner in the app.

set -euo pipefail

REPO_RAW="https://bandung-circuits.github.io/bootstrap/dsh-desktop"
_TMP_TEMPLATES_DIR=""

note() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() { [ -n "$_TMP_TEMPLATES_DIR" ] && rm -rf "$_TMP_TEMPLATES_DIR"; return 0; }
trap cleanup EXIT

fetch() {
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"
  else wget -qO "$2" "$1"; fi
}

# Resolve the template trees (local clone beside this script, else fetched from
# Pages for the piped curl|bash case).
load_templates() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null || true)"
  if [ -d "${script_dir}/templates/workspace" ]; then
    TEMPLATES_WORKSPACE="${script_dir}/templates/workspace"
    TEMPLATES_PATCH="${script_dir}/templates/dsh-desktop"
  else
    _TMP_TEMPLATES_DIR="$(mktemp -d)"
    mkdir -p "${_TMP_TEMPLATES_DIR}/workspace" "${_TMP_TEMPLATES_DIR}/dsh-desktop"
    for f in AGENTS.md README.md _gitignore NEXT-STEPS.md; do
      fetch "${REPO_RAW}/templates/workspace/${f}" "${_TMP_TEMPLATES_DIR}/workspace/${f}" || err "failed to fetch ${f}"
    done
    fetch "${REPO_RAW}/templates/dsh-desktop/crawl4ai-patch.yml" "${_TMP_TEMPLATES_DIR}/dsh-desktop/crawl4ai-patch.yml" || err "failed to fetch crawl4ai-patch.yml"
    TEMPLATES_WORKSPACE="${_TMP_TEMPLATES_DIR}/workspace"
    TEMPLATES_PATCH="${_TMP_TEMPLATES_DIR}/dsh-desktop"
  fi
  export TEMPLATES_WORKSPACE TEMPLATES_PATCH
}

# ---------- paths (env-overridable for tests) ----------
WORKSPACE_DIR="${WORKSPACE_DIR:-${HOME}/ai-workspace}"
APP_SUPPORT="${HOME}/Library/Application Support/DSH Desktop"
HARNESS_HOME="${DSH_HOME:-${APP_SUPPORT}/harness}"
UV_BIN="${WORKSPACE_DIR}/.local/bin/uv"
VENV_DIR="${WORKSPACE_DIR}/.venv"
VENV_PY="${VENV_DIR}/bin/python"
BROWSERS_DIR="${WORKSPACE_DIR}/.browsers"
CRAWL4AI_BIN="${VENV_DIR}/bin/crawl4ai-search"

# ---------- 1. workspace seeds ----------
seed_workspace() {
  mkdir -p "$WORKSPACE_DIR"
  local pairs="AGENTS.md:AGENTS.md README.md:README.md _gitignore:.gitignore NEXT-STEPS.md:NEXT-STEPS.md"
  local pair src dst
  for pair in $pairs; do
    src="${pair%%:*}"; dst="${pair##*:}"
    [ -f "$WORKSPACE_DIR/$dst" ] && { note "kept existing $WORKSPACE_DIR/$dst"; continue; }
    cp "${TEMPLATES_WORKSPACE}/${src}" "$WORKSPACE_DIR/$dst"
    note "seeded $WORKSPACE_DIR/$dst"
  done
}

# ---------- 2. uv into the workspace ----------
ensure_uv() {
  [ -x "$UV_BIN" ] && { note "uv present ($UV_BIN)"; return 0; }
  if [ "${PREP_NO_UV:-0}" = "1" ]; then
    note "skipping uv install (PREP_NO_UV=1)"; return 0
  fi
  note "installing uv into $WORKSPACE_DIR/.local/bin"
  mkdir -p "$(dirname "$UV_BIN")"
  export UV_INSTALL_DIR="$(dirname "$UV_BIN")"
  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  else
    wget -qO- https://astral.sh/uv/install.sh | sh
  fi
  unset UV_INSTALL_DIR
  [ -x "$UV_BIN" ] || err "uv install finished but not found at $UV_BIN"
  note "uv $( "$UV_BIN" --version 2>/dev/null || true )"
}

# ---------- 3. venv + crawl4ai-search-mcp, all inside the workspace ----------
ensure_venv() {
  ensure_uv
  if [ ! -x "$CRAWL4AI_BIN" ]; then
    note "creating venv at $VENV_DIR and installing crawl4ai-search-mcp==0.1.1"
    "$UV_BIN" venv "$VENV_DIR"
    "$UV_BIN" pip install -p "$VENV_DIR" "crawl4ai-search-mcp==0.1.1"
  fi
  [ -x "$CRAWL4AI_BIN" ] || err "crawl4ai-search not found in venv ($CRAWL4AI_BIN)"
  note "crawl4ai-search at $CRAWL4AI_BIN"
  # sitecustomize.py: python imports it automatically at startup, so ANY venv
  # python (the MCP server AND direct `venv/bin/python` runs by the agent) has
  # crawl4ai's data + browser directed into the workspace. Otherwise crawl4ai
  # would default to the user's home (~/.crawl4ai) and get blocked by the
  # sandbox / litter the home dir.
  local sp sitecustomize
  sp="$("$VENV_PY" -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null)"
  [ -n "$sp" ] && [ -d "$sp" ] || sp="$VENV_DIR/lib/python"*"/site-packages"
  mkdir -p "$sp"
  sitecustomize="$sp/sitecustomize.py"
  if [ ! -f "$sitecustomize" ]; then
    cat > "$sitecustomize" <<'PY'
import os, sys
# sitecustomize: runs before anything else at every venv python startup.
# sys.prefix is the venv dir (~/ai-workspace/.venv); the workspace is its parent
# (works on macOS lib/python3.X/site-packages and Windows Lib/site-packages).
_WS = os.path.dirname(sys.prefix)
os.environ.setdefault('CRAWL4_AI_BASE_DIRECTORY', _WS)
os.environ.setdefault('PLAYWRIGHT_BROWSERS_PATH', os.path.join(_WS, '.browsers'))
PY
    note "wrote $sitecustomize (crawl4ai data/browser stay in the workspace)"
  else
    note "sitecustomize already present ($sitecustomize)"
  fi
}

# ---------- 4. pre-download the Playwright Chromium into the workspace ----------
ensure_browser() {
  if [ -f "${BROWSERS_DIR}/chromium-*/chrome-*/chrome" ] 2>/dev/null \
     || [ -d "$BROWSERS_DIR" ] && ls "$BROWSERS_DIR" >/dev/null 2>&1 && find "$BROWSERS_DIR" -maxdepth 3 -name 'chrome*' | grep -q .; then
    note "browser already present in $BROWSERS_DIR"; return 0
  fi
  if [ "${PREP_NO_BROWSER:-0}" = "1" ]; then
    note "skipping browser pre-download (PREP_NO_BROWSER=1)"; return 0
  fi
  note "pre-downloading the Chromium browser into $BROWSERS_DIR (first search will need no download)"
  mkdir -p "$BROWSERS_DIR"
  if PLAYWRIGHT_BROWSERS_PATH="$BROWSERS_DIR" "$VENV_PY" -m playwright install chromium \
      > /tmp/dsh-prep-playwright.log 2>&1; then
    note "browser ready"
  else
    warn "browser pre-download failed (see /tmp/dsh-prep-playwright.log); first search will download it automatically"
  fi
}

# ---------- 5. crawl4ai MCP (official mcp-client), self-contained ----------
ensure_mcp_crawl4ai() {
  local patch="${HARNESS_HOME}/cordis.patch.yml"
  mkdir -p "$HARNESS_HOME"
  if [ -f "$patch" ] && grep -q 'mcp-crawl4ai' "$patch"; then
    note "crawl4ai MCP already enabled in $patch"
    return 0
  fi
  local block
  block="$(sed -e "s|{{CRAWL4AI_BIN}}|${CRAWL4AI_BIN}|g" \
                -e "s|{{WORKSPACE}}|${WORKSPACE_DIR}|g" \
                "${TEMPLATES_PATCH}/crawl4ai-patch.yml" || true)"
  if [ ! -f "$patch" ]; then
    printf '# DSH Desktop harness home-level patch (applies to every profile)\n' > "$patch"
  else
    printf '\n' >> "$patch"
  fi
  printf '%s\n' "$block" >> "$patch"
  note "enabled crawl4ai MCP in $patch"
}

# ---------- 6. default permission preset: Full Access (danger-full-access) ----------
ensure_permission_default() {
  local settings="${HARNESS_HOME}/settings.yaml"
  mkdir -p "$HARNESS_HOME"
  # workspace-write + ask is the stock default for new sessions: writes outside
  # the workspace are blocked and every escalation prompts -- painful for novice
  # learners. Pin danger-full-access (open sandbox, approval never) so the agent
  # can install/run what prep put in the workspace without prompt walls.
  if [ -f "$settings" ] && grep -q '^[[:space:]]*defaultPreset:' "$settings"; then
    note "permission default already set in $settings"
    return 0
  fi
  note "setting default permission preset to danger-full-access in $settings"
  if [ ! -f "$settings" ]; then
    printf 'permission:\n  defaultPreset: danger-full-access\n' > "$settings"
  elif grep -q '^permission:' "$settings"; then
    awk '/^permission:/ { print; print "  defaultPreset: danger-full-access"; next } { print }' \
      "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"
  else
    printf '\npermission:\n  defaultPreset: danger-full-access\n' >> "$settings"
  fi
  note "done"
}

# ---------- main ----------
main() {
  load_templates
  note "Creating and seeding ~/ai-workspace"
  seed_workspace
  note "Installing uv into the workspace"
  ensure_uv
  note "Creating the workspace venv with crawl4ai"
  ensure_venv
  note "Pre-downloading the Chromium browser"
  ensure_browser
  note "Enabling crawl4ai MCP (official DSH mcp-client)"
  ensure_mcp_crawl4ai
  note "Setting the default permission preset"
  ensure_permission_default

  if [ ! -d "$APP_SUPPORT" ]; then
    warn "DSH Desktop app data not found at $APP_SUPPORT — install DSH Desktop"
    warn "from https://dshdesktop.com/en/ and launch it once, then re-run this if needed."
  fi

  note "Done."
  cat <<NEXT

  Your AI workspace is ready at  ~/ai-workspace  (everything self-contained)

    Python / venv:    ~/ai-workspace/.venv
    crawl4ai MCP:     enabled via the official DSH MCP client
    Browser:          pre-downloaded to ~/ai-workspace/.browsers

  Remaining steps (2 clicks in the app):
    1. Open DSH Desktop → Settings → Models → paste your model API key.
    2. Choose workspace → ~/ai-workspace.

  See ~/ai-workspace/NEXT-STEPS.md for details.
NEXT
}

main "$@"