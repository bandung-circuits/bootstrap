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
# What it does:
#   1. Creates ~/ai-workspace and seeds AGENTS.md / README.md / .gitignore /
#      NEXT-STEPS.md (existing files are left alone).
#   2. Installs uv/uvx under ~/.local/bin — the runner the crawl4ai MCP uses.
#   3. Enables the crawl4ai MCP server through the OFFICIAL
#      @deepseek-ai/dsh-mcp-client (bundled with DSH Desktop — no plugin install)
#      by appending one insert to the app's harness patch
#      ~/Library/Application Support/DSH Desktop/harness/cordis.patch.yml.
#
# The model backend key is entered by the learner in the app (Settings → Models);
# this script never touches model credentials.

set -euo pipefail

REPO_RAW="https://bandung-circuits.github.io/bootstrap/dsh-desktop"
_TMP_TEMPLATES_DIR=""

# ---------- logging ----------
note() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- helpers ----------
cleanup() { [ -n "$_TMP_TEMPLATES_DIR" ] && rm -rf "$_TMP_TEMPLATES_DIR"; return 0; }
trap cleanup EXIT

fetch() { # fetch <url> <out>
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  else
    wget -qO "$2" "$1"
  fi
}

# Resolve the template trees: local clone beside this script, else fetched from
# Pages (the piped `curl | bash` case).
# Sets: TEMPLATES_WORKSPACE, TEMPLATES_PATCH
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
      fetch "${REPO_RAW}/templates/workspace/${f}" "${_TMP_TEMPLATES_DIR}/workspace/${f}" \
        || err "failed to fetch templates/workspace/${f}"
    done
    fetch "${REPO_RAW}/templates/dsh-desktop/crawl4ai-patch.yml" "${_TMP_TEMPLATES_DIR}/dsh-desktop/crawl4ai-patch.yml" \
      || err "failed to fetch templates/dsh-desktop/crawl4ai-patch.yml"
    TEMPLATES_WORKSPACE="${_TMP_TEMPLATES_DIR}/workspace"
    TEMPLATES_PATCH="${_TMP_TEMPLATES_DIR}/dsh-desktop"
  fi
  export TEMPLATES_WORKSPACE TEMPLATES_PATCH
}

# ---------- paths (env-overridable for tests) ----------
WORKSPACE_DIR="${WORKSPACE_DIR:-${HOME}/ai-workspace}"
APP_SUPPORT="${HOME}/Library/Application Support/DSH Desktop"
HARNESS_HOME="${DSH_HOME:-${APP_SUPPORT}/harness}"
UV_DIR="${UV_DIR:-${HOME}/.local/bin}"
UVX_BIN="${UV_DIR}/uvx"

# ---------- 1. workspace ----------
seed_workspace() {
  mkdir -p "$WORKSPACE_DIR"
  # template-name:installed-name (template names never match installed names,
  # so repo/global .gitignore and Pages rules cannot drop them)
  local pairs="AGENTS.md:AGENTS.md README.md:README.md _gitignore:.gitignore NEXT-STEPS.md:NEXT-STEPS.md"
  local pair src dst
  for pair in $pairs; do
    src="${pair%%:*}"; dst="${pair##*:}"
    [ -f "$WORKSPACE_DIR/$dst" ] && { note "kept existing $WORKSPACE_DIR/$dst"; continue; }
    cp "${TEMPLATES_WORKSPACE}/${src}" "$WORKSPACE_DIR/$dst"
    note "seeded $WORKSPACE_DIR/$dst"
  done
}

# ---------- 2. uv/uvx ----------
ensure_uv() {
  [ -x "$UVX_BIN" ] && { note "uvx present ($UVX_BIN)"; return 0; }
  if [ "${PREP_NO_UV:-0}" = "1" ]; then
    note "skipping uv install (PREP_NO_UV=1)"; return 0
  fi
  note "installing uv/uvx into $UV_DIR (the runner crawl4ai uses)"
  mkdir -p "$UV_DIR"
  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  else
    wget -qO- https://astral.sh/uv/install.sh | sh
  fi
  [ -x "$UVX_BIN" ] || err "uv install finished but uvx not found at $UVX_BIN"
  note "uv installed ($(uv --version 2>/dev/null || true))"
}

# ---------- 3. crawl4ai MCP (official mcp-client) ----------
ensure_mcp_crawl4ai() {
  local patch="${HARNESS_HOME}/cordis.patch.yml"
  mkdir -p "$HARNESS_HOME"
  if [ -f "$patch" ] && grep -q 'mcp-crawl4ai' "$patch"; then
    note "crawl4ai MCP already enabled in $patch"
    return 0
  fi
  [ -x "$UVX_BIN" ] || err "uvx not found at $UVX_BIN — run install/uv step first"
  # Render the patch insert: absolute uvx path (the app process does not carry
  # ~/.local/bin on PATH) + the workspace as the server's cwd.
  local block
  block="$(sed -e "s|{{UVX_BIN}}|${UVX_BIN}|g" \
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

# ---------- main ----------
main() {
  load_templates

  note "Creating and seeding ~/ai-workspace"
  seed_workspace

  note "Installing uv/uvx (crawl4ai runtime)"
  ensure_uv

  note "Enabling crawl4ai MCP (official DSH mcp-client)"
  ensure_mcp_crawl4ai

  if [ ! -d "$APP_SUPPORT" ]; then
    warn "DSH Desktop app data not found at $APP_SUPPORT — install DSH Desktop"
    warn "from https://dshdesktop.com/en/ and launch it once, then re-run this if needed."
  fi

  note "Done."
  cat <<NEXT

  Your AI workspace is ready at  ~/ai-workspace

  Remaining steps (2 clicks in the app):
    1. Open DSH Desktop → Settings → Models → paste your DeepSeek API key.
    2. Choose workspace → ~/ai-workspace.

  The crawl4ai MCP (web fetch/search) is enabled through the official DSH MCP
  client. First search downloads a small helper environment automatically.

  See ~/ai-workspace/NEXT-STEPS.md for details.
NEXT
}

main "$@"