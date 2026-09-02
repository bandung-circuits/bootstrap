#!/usr/bin/env bash
# claude-code.sh — install the Claude Code extension for VS Code.
# The extension runs inside VS Code's own runtime (no separate Node.js or
# standalone `claude` CLI needed). Backend model is wired up via settings.json
# in lib/provider.sh.

# Claude Code for VS Code — marketplace ID (verified).
CLAUDE_CODE_EXT_ID="anthropic.claude-code"

claude_code_extension_install() {
  command -v code >/dev/null 2>&1 || err "'code' command not found; cannot install extension"
  if code --list-extensions 2>/dev/null | grep -qi "^$CLAUDE_CODE_EXT_ID$"; then
    note "Claude Code VS Code extension already installed"
  else
    note "installing Claude Code VS Code extension"
    code --install-extension "$CLAUDE_CODE_EXT_ID" --force \
      || err "failed to install extension $CLAUDE_CODE_EXT_ID"
  fi
  # Suppress GitHub Copilot so the only AI chat surface is Claude Code.
  # Best-effort: built-in Copilot can't be uninstalled, only disabled via
  # settings (see vscode_write_user_settings); marketplace Copilot is removed.
  for ext in github.copilot github.copilot-chat; do
    code --uninstall-extension "$ext" >/dev/null 2>&1 || true
  done
}
