#!/usr/bin/env bash
# install-wsl.sh — thin wrapper for WSL users.
# Inside WSL, VS Code's "Remote - WSL" experience is driven by the Windows VS Code
# binary calling back into WSL. This wrapper runs the normal Linux install (Node,
# claude-code CLI, settings.json, crawl4ai, workspace) and ensures the Windows
# side has VS Code installed too.
#
# Typical flow (documented on the site): run `wsl --install` in PowerShell, reboot,
# then inside the WSL shell:  curl -fsSL <site>/install-wsl.sh | bash

set -euo pipefail

REPO_RAW="https://bandung-circuits.github.io/bootstrap/vscode"

note(){ printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
err(){ printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

grep -qi microsoft /proc/version 2>/dev/null || warn "this script targets WSL; on plain Linux use install.sh"

# Pull and run the standard installer; it auto-detects WSL as DETECT_OS=wsl
# and installs the Linux side (Node, claude-code CLI, settings, crawl4ai, workspace).
note "running standard Linux installer inside WSL"
exec bash -c 'curl -fsSL "'"${REPO_RAW}"'/install.sh" | bash -s -- "$@"' -- "$@"

# Note for WSL users (printed by the installer's final hints):
#   - To open VS Code in the WSL workspace, run `code ~/ai-workspace` from WSL;
#     VS Code's Remote-WSL opens automatically if the Windows VS Code + WSL extension
#     are installed. If `code` is not on the WSL PATH, run it from Windows PowerShell:
#       code \\\\wsl$\\<distro>\\home\\<you>\\ai-workspace
