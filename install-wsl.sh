#!/usr/bin/env bash
# LEGACY ENTRY — forwards to the VS Code + Claude Code scheme in vscode/.
#
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/install-wsl.sh | bash
set -euo pipefail
exec bash -c 'curl -fsSL "https://bandung-circuits.github.io/bootstrap/vscode/install-wsl.sh" | bash -s -- "$@"' -- "$@"