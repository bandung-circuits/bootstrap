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

  --provider=bailian|deepseek|openrouter   override auto region routing
  --api-key=KEY                            pass API key non-interactively

Default routing: China -> Alibaba Bailian; elsewhere -> DeepSeek official.
U
}

# ---------- lib loading ----------
cleanup() { [ -n "$_TMP_LIB_DIR" ] && rm -rf "$_TMP_LIB_DIR"; }
trap cleanup EXIT

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
    curl -fsSL "${REPO_RAW}/lib/${f}" -o "${_TMP_LIB_DIR}/${f}" \
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

  note "Installing Node.js + Claude Code CLI + extension"
  claude_code_install_all

  note "Configuring Claude Code backend (settings.json)"
  provider_write_settings

  note "Installing crawl4ai MCP"
  crawl4ai_install
  crawl4ai_postinstall_hint

  note "Creating default AI workspace"
  workspace_create

  note "Done."
  cat <<'NEXT'

  Next steps:
  1. Visual Studio Code opens in  ~/ai-workspace  (your default workspace).
  2. Open the Claude Code panel (sidebar). Sign-in step is skipped — the
     backend is already configured to DeepSeek V4 Flash 0731 via your API key.
  3. Run  /model  in the Claude Code panel to confirm the active model.
  4. Try asking it something: e.g. "create a hello.py and run it".

  The crawl4ai MCP (web fetch/search) is also registered and ready.
NEXT
  workspace_open
}

main "$@"
