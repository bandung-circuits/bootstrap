#!/usr/bin/env bash
# bootstrap vscode/install.sh — one-command setup of VS Code + Claude Code + DeepSeek V4 Flash 0731.
#
# Usage (Linux/macOS):
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/vscode/install.sh | bash
# or from a clone:
#   ./vscode/install.sh [--provider=bailian|deepseek|openrouter] [--api-key=KEY]
#
# When piped via curl|bash, the lib/*.sh modules and templates/ files are
# fetched from the GitHub Pages URL (github.io is reachable in mainland China;
# raw.githubusercontent is often blocked). When run from a clone, local lib/ and
# templates/ are used. The shared detect.sh lives at the repo root lib/ (both
# the vscode and dsh schemes use it).

set -euo pipefail

REPO_RAW="https://bandung-circuits.github.io/bootstrap/vscode"
REPO_ROOT_RAW="https://bandung-circuits.github.io/bootstrap"
LIB_FILES=(provider.sh vscode.sh claude-code.sh crawl4ai.sh workspace.sh)
_TMP_LIB_DIR=""
_TMP_TEMPLATES_DIR=""

# ---------- logging ----------
note() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- arg parsing ----------
parse_args() {
  for arg in "$@"; do
    case "$arg" in
      --provider=*)    PROVIDER="${arg#*=}" ;;
      --api-key=*)     PROVIDER_API_KEY="${arg#*=}" ;;
      --provider|-p)   shift=1 ;;
      --help|-h)      usage; exit 0 ;;
      *) err "unknown argument: $arg" ;;
    esac
  done
}

usage() {
  cat <<'U'
bootstrap — set up VS Code + Claude Code + DeepSeek V4 Flash 0731. (Fallback
scheme; the recommended scheme is DeepSeek Harness / dsh, see ../dsh/install.sh.)

  --provider=bailian|bailian-intl|deepseek|openrouter   override auto region routing
  --api-key=KEY                            (optional) bake the key into settings;
                                           if omitted, a placeholder is written
                                           and NEXT-STEPS.md tells you how to add it

Default routing: China -> Alibaba Bailian (domestic); elsewhere -> Alibaba Cloud
Model Studio (international). The installer never prompts — it writes a template
config + NEXT-STEPS.md.
U
}

# ---------- lib loading ----------
cleanup() {
  [ -n "$_TMP_LIB_DIR" ] && rm -rf "$_TMP_LIB_DIR"
  [ -n "$_TMP_TEMPLATES_DIR" ] && rm -rf "$_TMP_TEMPLATES_DIR"
  return 0
}
trap cleanup EXIT

# Fetch a URL to a file, using curl if available, else wget.
fetch() { # fetch <url> <out>
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  else
    wget -qO "$2" "$1"
  fi
}

# Resolve ./vscode/templates/workspace — the static files seeded into the AI
# workspace. Local clone: the dir beside the script. Piped: fetched with the
# libs into a temp dir.
# Sets: TEMPLATES_DIR
load_templates() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null || true)"
  if [ -d "${script_dir}/templates/workspace" ]; then
    TEMPLATES_DIR="${script_dir}/templates/workspace"
    return
  fi
  _TMP_TEMPLATES_DIR="$(mktemp -d)"
  for f in README.md .gitignore CLAUDE.md NEXT-STEPS.md; do
    fetch "${REPO_RAW}/templates/workspace/${f}" "${_TMP_TEMPLATES_DIR}/${f}" \
      || err "failed to fetch templates/workspace/${f} from repo"
  done
  mkdir -p "${_TMP_TEMPLATES_DIR}/.vscode" "${_TMP_TEMPLATES_DIR}/.claude"
  fetch "${REPO_RAW}/templates/workspace/.vscode/settings.json" "${_TMP_TEMPLATES_DIR}/.vscode/settings.json" \
    || err "failed to fetch templates/workspace/.vscode/settings.json"
  fetch "${REPO_RAW}/templates/workspace/.claude/settings.local.json" "${_TMP_TEMPLATES_DIR}/.claude/settings.local.json" \
    || err "failed to fetch templates/workspace/.claude/settings.local.json"
  TEMPLATES_DIR="$_TMP_TEMPLATES_DIR"
  export TEMPLATES_DIR
}

load_libs() {
  local script_dir
  # If run from a clone: shared detect.sh at repo root lib/, scheme libs beside
  # this script.
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null || true)"
  if [ -f "${script_dir}/lib/provider.sh" ]; then
    . "$(cd "$script_dir/.." && pwd)/lib/detect.sh"
    for f in "${LIB_FILES[@]}"; do . "${script_dir}/lib/${f}"; done
    load_templates
    return
  fi
  # Piped via curl|bash: fetch libs into a temp dir.
  _TMP_LIB_DIR="$(mktemp -d)"
  for f in "${LIB_FILES[@]}"; do
    fetch "${REPO_RAW}/lib/${f}" "${_TMP_LIB_DIR}/${f}" \
      || err "failed to fetch lib/${f} from repo"
    . "${_TMP_LIB_DIR}/${f}"
  done
  # Shared detect.sh comes from the repo root.
  fetch "${REPO_ROOT_RAW}/lib/detect.sh" "${_TMP_LIB_DIR}/detect.sh" \
    || err "failed to fetch shared lib/detect.sh"
  . "${_TMP_LIB_DIR}/detect.sh"
  load_templates
}

# ---------- main ----------
main() {
  parse_args "$@"
  load_libs

  note "Detecting environment"
  detect_all
  detect_print

  note "Resolving provider"
  provider_resolve
  provider_print

  provider_ensure_key

  note "Installing Visual Studio Code"
  vscode_install

  note "Installing Claude Code VS Code extension"
  claude_code_extension_install

  note "Setting VS Code defaults (skip welcome, trust on, Edit-automatically mode)"
  vscode_write_user_settings

  note "Creating default AI workspace"
  workspace_create

  note "Configuring Claude Code backend (settings.local.json in workspace)"
  provider_write_settings
  provider_write_next_steps

  note "Installing crawl4ai MCP"
  crawl4ai_install
  crawl4ai_postinstall_hint

  note "Seeding VS Code UI state (skip first-run onboarding/theme picker)"
  vscode_seed_state

  note "Done."
  cat <<'NEXT'

  Almost ready! One step left: add your API key.
  See  ~/ai-workspace/NEXT-STEPS.md  (open it: it tells you where to get a key,
  which file to edit, and how to start Claude Code).

  Then VS Code opens in  ~/ai-workspace  -- Claude Code opens in the right
  sidebar, ready to use.
  The crawl4ai MCP (web fetch/search) is registered and ready.
NEXT
  workspace_open
}

main "$@"
