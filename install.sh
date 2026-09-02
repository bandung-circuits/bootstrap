#!/usr/bin/env bash
# LEGACY ENTRY — kept so the original documented one-liner still works after the
# VS Code + Claude Code scheme moved into vscode/. It forwards to the vscode
# scheme verbatim (the recommended scheme is DeepSeek Harness / dsh,
# see https://bandung-circuits.github.io/bootstrap/dsh/install.sh ).
#
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/install.sh | bash

set -euo pipefail
exec bash -c 'curl -fsSL "https://bandung-circuits.github.io/bootstrap/vscode/install.sh" | bash -s -- "$@"' -- "$@"