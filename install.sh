#!/usr/bin/env bash
# bootstrap install.sh — one-command setup of VS Code + Claude Code + DeepSeek V4 Flash 0731.
#
# Usage (Linux/macOS):
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/install.sh | bash
# or from a clone:
#   ./install.sh [--provider=bailian|deepseek|openrouter] [--api-key=KEY]
#
# When piped via curl|bash, the lib/*.sh modules are fetched from the GitHub
# Pages URL (github.io is reachable in mainland China; raw.githubusercontent is
# often blocked). When run from a clone, the local lib/ is used.

set -euo pipefail

REPO_RAW="https://bandung-circuits.github.io/bootstrap"
LIB_FILES=(detect.sh provider.sh vscode.sh claude-code.sh crawl4ai.sh workspace.sh)
_TMP_LIB_DIR=""

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
bootstrap — set up VS Code + Claude Code + DeepSeek V4 Flash 0731.

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
cleanup() { [ -n "$_TMP_LIB_DIR" ] && rm -rf "$_TMP_LIB_DIR"; }
trap cleanup EXIT

# Fetch a URL to a file, using curl if available, else wget.
fetch() { # fetch <url> <out>
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  else
    wget -qO "$2" "$1"
  fi
}

load_libs() {
  local script_dir
  # If run from a clone, lib/ sits next to this script.
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null || true)"
  if [ -f "${script_dir}/lib/detect.sh" ]; then
    for f in "${LIB_FILES[@]}"; do . "${script_dir}/lib/${f}"; done
    return
  fi
  # Piped via curl|bash: fetch libs into a temp dir.
  _TMP_LIB_DIR="$(mktemp -d)"
  for f in "${LIB_FILES[@]}"; do
    fetch "${REPO_RAW}/lib/${f}" "${_TMP_LIB_DIR}/${f}" \
      || err "failed to fetch lib/${f} from repo"
    . "${_TMP_LIB_DIR}/${f}"
  done
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

  note "Done."
  cat <<'NEXT'

  Almost ready! One step left: add your API key.
  See  ~/ai-workspace/NEXT-STEPS.md  (open it: it tells you where to get a key,
  which file to edit, and how to start Claude Code).

  Then VS Code opens in  ~/ai-workspace  with the Claude Code panel ready.
  The crawl4ai MCP (web fetch/search) is registered and ready.
NEXT
  workspace_open
}

main "$@"
