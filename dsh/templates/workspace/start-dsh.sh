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

# Load machine-local secrets into the environment. dsh refuses to read
# launch-control variable names (e.g. DSH_API_KEY) from its own .env files
# (verified against dsh 0.1.1-rc.2), so the installer stores them in
# secrets.env and we export them here before dsh boots.
if [ -f "$DSH_HOME/secrets.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$DSH_HOME/secrets.env"
  set +a
fi

if ! command -v dsh >/dev/null 2>&1; then
  echo "dsh is not installed. Re-run the installer, then try again."
  exit 1
fi

echo "Starting DeepSeek Harness ... (browser opens at http://127.0.0.1:3080)"
echo "Press Ctrl+C to stop."
exec dsh web "$@"