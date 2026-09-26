#!/usr/bin/env bash
# dsh-desktop/cohort/cohort-setup.sh — full learner setup for a training cohort
# (macOS). One command, nothing pre-installed:
#
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh-desktop/cohort/cohort-setup.sh \
#     | TRAINING_API_KEY='sk-...' bash
#
# 1. Ensures DSH Desktop is installed — the shared front half
#    (../install-dsh.sh, pinned release, silent install) does this; this
#    script holds no install logic and no version pin.
# 2. Delegates everything else to cohort-prep.sh VERBATIM (public prep +
#    provider/key injection).
#
# Windows uses cohort-setup.ps1.

set -euo pipefail

REPO_BASE="https://bandung-circuits.github.io/bootstrap"
COHORT_PREP_URL="${COHORT_PREP_URL:-${REPO_BASE}/dsh-desktop/cohort/cohort-prep.sh}"
INSTALL_DSH_URL="${INSTALL_DSH_URL:-${REPO_BASE}/dsh-desktop/install-dsh.sh}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd 2>/dev/null || true)"

note() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# 0. fail fast on a missing key BEFORE downloading a ~175 MB installer.
: "${TRAINING_API_KEY:?TRAINING_API_KEY is missing — copy the command from your cohort page, not a generic one.}"

# 1. DSH Desktop itself (pinned) — shared front half with the public flow.
if [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/../install-dsh.sh" ]; then
  bash "${SCRIPT_DIR}/../install-dsh.sh"
else
  curl -fsSL "$INSTALL_DSH_URL" | bash
fi

# 2. everything else is exactly the existing cohort flow (public prep + inject).
# REUSE — no setup logic here. Env (key, model, …) flows through to the child.
note "Running the cohort workspace setup (workspace, web tools, model provider)"
if [ -f "$COHORT_PREP_URL" ]; then
  bash "$COHORT_PREP_URL"
else
  curl -fsSL "$COHORT_PREP_URL" | bash
fi
