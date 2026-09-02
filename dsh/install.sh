#!/usr/bin/env bash
# bootstrap dsh/install.sh — one-command setup of DeepSeek Harness (dsh) +
# DeepSeek V4 Flash 0731 + the crawl4ai MCP, in a self-contained ~/ai-workspace.
#
# Usage (Linux/macOS; WSL included — detect sees WSL and this runs as-is):
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh/install.sh | bash
# or from a clone:
#   ./dsh/install.sh [--provider=bailian|bailian-intl|deepseek|openrouter] \
#                    [--api-key=KEY] [--no-launch]
#
# When piped via curl|bash, lib/*.sh and templates/* are fetched from the
# GitHub Pages URL (github.io is reachable in mainland China; raw.githubusercontent
# is often blocked). When run from a clone, local files are used. The shared
# detect.sh lives at the repo root lib/ (both schemes use it).
#
# What it does: detects OS/arch/region, pins Node 24 LTS + @deepseek-ai/dsh
# (a dev-preview, so the exact versions matter — see lib/dsh.sh), writes the
# model provider route into ~/ai-workspace/.dsh/settings.yaml, your API key into
# ~/ai-workspace/.dsh/.env (mode 600), enables the crawl4ai MCP via the official
# mcp-client row in ~/ai-workspace/.dsh/cordis.patch.yml, seeds
# ~/ai-workspace (AGENTS.md, README, NEXT-STEPS, start-dsh launchers), and
# launches dsh web. Every seeded file is a real template under dsh/templates/ —
# nothing is embedded in this code.

set -euo pipefail

REPO_RAW="https://bandung-circuits.github.io/bootstrap/dsh"
REPO_ROOT_RAW="https://bandung-circuits.github.io/bootstrap"
LIB_FILES=(dsh.sh providers.sh config.sh mcp.sh workspace.sh)
_TMP_LIB_DIR=""
_TMP_TEMPLATES_DIR=""

# ---------- logging ----------
note() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- arg parsing ----------
parse_args() {
  BOOTSTRAP_NO_LAUNCH=0
  for arg in "$@"; do
    case "$arg" in
      --provider=*)    PROVIDER="${arg#*=}" ;;
      --api-key=*)     DSH_API_KEY="${arg#*=}" ;;
      --no-launch)     BOOTSTRAP_NO_LAUNCH=1 ;;
      --skip-dump)     BOOTSTRAP_SKIP_DUMP=1 ;;
      --help|-h)       usage; exit 0 ;;
      *) err "unknown argument: $arg" ;;
    esac
  done
  export BOOTSTRAP_NO_LAUNCH BOOTSTRAP_SKIP_DUMP DSH_API_KEY
}

usage() {
  cat <<'U'
bootstrap (dsh) — set up DeepSeek Harness + DeepSeek V4 Flash 0731. The
recommended scheme; the VS Code + Claude Code alternative lives in vscode/.

  --provider=bailian|bailian-intl|deepseek|openrouter   override auto region routing
  --api-key=KEY                             (optional) bake the key into
                                            ~/ai-workspace/.dsh/.env; if omitted,
                                            a placeholder is written and
                                            NEXT-STEPS.md tells you how to add it
  --no-launch                              don't start dsh web at the end
  --skip-dump                              don't run `dsh web --dump-config`

Default routing: China -> Alibaba Bailian (domestic); elsewhere -> Alibaba Cloud
Model Studio (international). The installer never prompts.
U
}

# ---------- lib/templates loading ----------
cleanup() {
  [ -n "$_TMP_LIB_DIR" ] && rm -rf "$_TMP_LIB_DIR"
  [ -n "$_TMP_TEMPLATES_DIR" ] && rm -rf "$_TMP_TEMPLATES_DIR"
}
trap cleanup EXIT

fetch() { # fetch <url> <out>
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2"
  else
    wget -qO "$2" "$1"
  fi
}

# Resolve the two template trees (workspace + dsh-home). Local clone: beside the
# script. Piped: fetched with the libs.
# Sets: TEMPLATES_DIR, TEMPLATES_DSH_HOME
load_templates() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null || true)"
  if [ -d "${script_dir}/templates/workspace" ]; then
    TEMPLATES_DIR="${script_dir}/templates/workspace"
    TEMPLATES_DSH_HOME="${script_dir}/templates/dsh-home"
    export TEMPLATES_DIR TEMPLATES_DSH_HOME
    return
  fi
  _TMP_TEMPLATES_DIR="$(mktemp -d)"
  mkdir -p "${_TMP_TEMPLATES_DIR}/workspace" "${_TMP_TEMPLATES_DIR}/dsh-home"
  for f in AGENTS.md README.md .gitignore NEXT-STEPS.md start-dsh.sh start-dsh.cmd start-dsh.ps1; do
    fetch "${REPO_RAW}/templates/workspace/${f}" "${_TMP_TEMPLATES_DIR}/workspace/${f}" \
      || err "failed to fetch templates/workspace/${f}"
  done
  for f in settings.yaml cordis.patch.yml crawl4ai-row.yml .env .gitignore; do
    fetch "${REPO_RAW}/templates/dsh-home/${f}" "${_TMP_TEMPLATES_DIR}/dsh-home/${f}" \
      || err "failed to fetch templates/dsh-home/${f}"
  done
  TEMPLATES_DIR="${_TMP_TEMPLATES_DIR}/workspace"
  TEMPLATES_DSH_HOME="${_TMP_TEMPLATES_DIR}/dsh-home"
  export TEMPLATES_DIR TEMPLATES_DSH_HOME
}

load_libs() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null || true)"
  if [ -f "${script_dir}/lib/dsh.sh" ]; then
    . "$(cd "$script_dir/.." && pwd)/lib/detect.sh"
    for f in "${LIB_FILES[@]}"; do . "${script_dir}/lib/${f}"; done
    load_templates
    return
  fi
  _TMP_LIB_DIR="$(mktemp -d)"
  for f in "${LIB_FILES[@]}"; do
    fetch "${REPO_RAW}/lib/${f}" "${_TMP_LIB_DIR}/${f}" \
      || err "failed to fetch lib/${f}"
    . "${_TMP_LIB_DIR}/${f}"
  done
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

  note "Resolving model provider"
  provider_resolve
  provider_print
  provider_ensure_key

  note "Installing Node (pinned LTS ${NODE_MAJOR}.x) and the dsh CLI (${DSH_NPM_PKG})"
  node_install
  dsh_install

  note "Creating the AI workspace and seeding ~/ai-workspace"
  workspace_create

  note "Seeding the DeepSeek Harness home (~/ai-workspace/.dsh)"
  dsh_home_create

  dsh_smoke

  note "Done."
  cat <<NEXT

  Almost ready! One step left: add your API key (unless you passed --api-key).
  See  ~/ai-workspace/NEXT-STEPS.md  — it tells you where to get a key and
  how to paste it into  ~/ai-workspace/.dsh/.env  (or use Settings -> Models
  in the Web UI). Then start the assistant from the workspace:
      ~/ai-workspace/start-dsh.sh
  or double-click  start-dsh.cmd  on Windows. The browser opens
  http://127.0.0.1:3080  and crawl4ai MCP (web fetch/search) is ready.
NEXT

  if [ "${BOOTSTRAP_NO_LAUNCH:-0}" = "1" ]; then
    note "skipping launch (--no-launch)"
    return 0
  fi
  if [ -f "$WORKSPACE_DIR/start-dsh.sh" ]; then
    note "launching DeepSeek Harness in the background"
    nohup "$WORKSPACE_DIR/start-dsh.sh" >/dev/null 2>&1 & disown || true
    note "if the browser did not open, run: $WORKSPACE_DIR/start-dsh.sh"
  else
    warn "open a terminal and run: $WORKSPACE_DIR/start-dsh.sh"
  fi
}

main "$@"