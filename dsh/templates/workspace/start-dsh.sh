#!/usr/bin/env bash
# Start DeepSeek Harness (dsh) Web UI in this workspace, with its home at
# ~/ai-workspace/.dsh. The workspace root is this folder (where AGENTS.md lives).
set -euo pipefail
cd "$(dirname "$0")"
export DSH_HOME="$PWD/.dsh"

# The dsh CLI and its Node runtime may live under ~/.local — make sure they are
# findable even if this terminal has a fresh PATH.
case ":$PATH:" in
  *":$HOME/.local/bin:"*);;
  *) export PATH="$HOME/.local/bin:$HOME/.local/nodejs/bin:$PATH";;
esac

if ! command -v dsh >/dev/null 2>&1; then
  echo "dsh is not installed. Re-run the installer, then try again."
  exit 1
fi

echo "Starting DeepSeek Harness ... (browser opens at http://127.0.0.1:3080)"
echo "Press Ctrl+C to stop."
exec dsh web "$@"