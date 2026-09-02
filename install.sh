#!/usr/bin/env bash
# LEGACY ENTRY — kept so the original documented one-liner still works after the
# VS Code + Claude Code scheme moved into vscode/. Forwards to the vscode scheme
# verbatim. (The DSH Desktop path has its own page: dsh-desktop.html)
#
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/install.sh | bash
set -euo pipefail
exec bash -c 'curl -fsSL "https://bandung-circuits.github.io/bootstrap/vscode/install.sh" | bash -s -- "$@"' -- "$@"