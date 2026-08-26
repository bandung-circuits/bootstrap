#!/usr/bin/env bash
# claude-code.sh — install Node.js, Claude Code CLI, and the VS Code extension.

# Claude Code VS Code extension marketplace ID.
CLAUDE_CODE_EXT_ID="anthropic.claude-code"

node_is_installed() {
  command -v node >/dev/null 2>&1 && node --version >/dev/null 2>&1
}

node_install() {
  if node_is_installed; then note "Node.js already installed ($(node --version))"; return 0; fi
  case "$DETECT_OS" in
    macos)
      [ -n "$DETECT_PKG_MANAGER" ] || err "Homebrew not found. Install: https://brew.sh"
      note "installing Node.js via Homebrew"
      brew install node
      ;;
    linux|wsl)
      case "$DETECT_PKG_MANAGER" in
        apt)
          note "installing Node.js (NodeSource) via apt"
          sudo apt-get install -y curl ca-certificates git
          curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo bash -
          sudo apt-get install -y nodejs
          ;;
        dnf) sudo dnf install -y nodejs npm ;;
        yum) sudo yum install -y nodejs npm ;;
        pacman) sudo pacman -S --noconfirm nodejs npm ;;
        *) err "no supported package manager for Node install" ;;
      esac
      ;;
    *) err "Node install not supported on $DETECT_OS here" ;;
  esac
  node_is_installed || err "Node.js install failed"
}

claude_code_cli_install() {
  if command -v claude >/dev/null 2>&1; then
    note "Claude Code CLI already installed"
  else
    note "installing Claude Code CLI (npm)"
    npm install -g @anthropic-ai/claude-code || err "Claude Code CLI install failed"
  fi
}

claude_code_extension_install() {
  command -v code >/dev/null 2>&1 || err "'code' command not found; cannot install extension"
  note "installing Claude Code VS Code extension"
  code --install-extension "$CLAUDE_CODE_EXT_ID" --force
}

claude_code_install_all() {
  node_install
  claude_code_cli_install
  claude_code_extension_install
}
