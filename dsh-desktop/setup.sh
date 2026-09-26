#!/usr/bin/env bash
# dsh-desktop/setup.sh — one-command bootstrap for DSH Desktop learners
# (public, macOS). Nothing pre-installed:
#
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh-desktop/setup.sh | bash
#
# 1. Ensures DSH Desktop itself is installed (pinned release, silent) by
#    running install-dsh.sh — the shared front half with the cohort flow.
# 2. Delegates everything else to prep.sh VERBATIM (workspace, venv +
#    crawl4ai, browser, crawl4ai MCP, permission default) — no setup logic
#    here. The model API key is intentionally NOT handled: the learner
#    pastes their own key in the app afterwards (Settings → Models).
#
# Windows uses setup.ps1. The training-cohort flow additionally injects a
# shared provider key (cohort/cohort-setup.sh) and is maintained separately.

set -euo pipefail

REPO_BASE="https://bandung-circuits.github.io/bootstrap"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null || true)"
PREP_URL="${PREP_URL:-${REPO_BASE}/dsh-desktop/prep.sh}"

# 1. DSH Desktop itself (pinned) — shared front half.
if [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/install-dsh.sh" ]; then
  bash "${SCRIPT_DIR}/install-dsh.sh"
else
  curl -fsSL "${REPO_BASE}/dsh-desktop/install-dsh.sh" | bash
fi

# 2. The workspace (public prep). REUSE — no setup logic here.
note() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
note "Setting up the AI workspace (workspace, web tools)"
if [ -f "$PREP_URL" ]; then
  bash "$PREP_URL"
else
  curl -fsSL "$PREP_URL" | bash
fi
