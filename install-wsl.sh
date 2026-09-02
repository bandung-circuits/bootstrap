#!/usr/bin/env bash
# LEGACY ENTRY — kept so the original documented one-liner still works after the
# VS Code + Claude Code scheme moved into vscode/.
#
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/install-wsl.sh | bash

set -euo pipefail
exec bash -c 'curl -fsSL "https://bandung-circuits.github.io/bootstrap/vscode/install-wsl.sh" | bash -s -- "$@"' -- "$@"