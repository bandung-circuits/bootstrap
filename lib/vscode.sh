#!/usr/bin/env bash
# vscode.sh — install Visual Studio Code. Sourced by install.sh.

vscode_is_installed() {
  command -v code >/dev/null 2>&1 && return 0
  # macOS GUI install doesn't put `code` on PATH by default; check app bundle.
  [ "$DETECT_OS" = "macos" ] && [ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ] && return 0
  return 1
}

vscode_install() {
  if vscode_is_installed; then note "VS Code already installed"; return 0; fi
  case "$DETECT_OS" in
    macos)
      if [ -z "$DETECT_PKG_MANAGER" ]; then
        err "Homebrew not found. Install Homebrew first: https://brew.sh"
      fi
      note "installing VS Code via Homebrew"
      brew install --cask visual-studio-code
      ;;
    linux|wsl)
      case "$DETECT_PKG_MANAGER" in
        apt)
          note "installing VS Code via apt (Microsoft source)"
          sudo apt-get update -y
          sudo apt-get install -y wget gpg
          wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
          sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
          echo "deb [arch=$DETECT_ARCH signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
            | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
          sudo apt-get update -y
          sudo apt-get install -y code
          ;;
        dnf)
          sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
          sudo dnf install -y "https://packages.microsoft.com/yumrepos/vscode/code-$DETECT_ARCH.rpm" || sudo dnf install -y code
          ;;
        yum)
          sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
          sudo yum install -y "https://packages.microsoft.com/yumrepos/vscode/code-$DETECT_ARCH.rpm" || sudo yum install -y code
          ;;
        pacman)
          sudo pacman -S --noconfirm code
          ;;
        *) err "no supported package manager found for VS Code install" ;;
      esac
      ;;
    *) err "VS Code install not supported on $DETECT_OS here" ;;
  esac
  vscode_link_cli
}

# On macOS, put the `code` shell command on PATH if missing.
vscode_link_cli() {
  [ "$DETECT_OS" = "macos" ] || return 0
  local target="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
  [ -x "$target" ] || return 0
  command -v code >/dev/null 2>&1 && return 0
  local bindir="${HOME}/.local/bin"
  mkdir -p "$bindir"
  ln -sf "$target" "$bindir/code"
  note "linked 'code' to $bindir (add $bindir to PATH if needed)"
}
