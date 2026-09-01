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
          sudo apt-get install -y wget gpg xdg-utils
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

# Path to the VS Code USER settings.json (per OS).
vscode_user_settings_path() {
  case "$DETECT_OS" in
    macos) printf '%s/Library/Application Support/Code/User/settings.json' "$HOME" ;;
    linux|wsl) printf '%s/.config/Code/User/settings.json' "$HOME" ;;
    windows) printf '%s\\AppData\\Roaming\\Code\\User\\settings.json' "$HOME" ;;
  esac
}

# Path to the VS Code UI-state DB (state.vscdb), per OS. Seeding the first-run
# onboarding/theme flags here suppresses the "choose interface style" picker
# that settings.json can't control. Keys seeded are portable (no machine paths).
vscode_state_db_path() {
  case "$DETECT_OS" in
    macos) printf '%s/Library/Application Support/Code/User/globalStorage/state.vscdb' "$HOME" ;;
    linux|wsl) printf '%s/.config/Code/User/globalStorage/state.vscdb' "$HOME" ;;
    windows) printf '%s\\AppData\\Roaming\\Code\\User\\globalStorage\\state.vscdb' "$HOME" ;;
  esac
}

# Write VS Code user settings to make first-run frictionless:
#   - no Welcome tab / walkthroughs / release notes
#   - workspace trust disabled (no Restricted Mode prompt)
#   - Claude Code extension starts in "Edit automatically" mode
#   - Claude Code opens in the sidebar (right), login prompt skipped
#     (third-party provider), onboarding checklist hidden
#   - Copilot completions disabled + its command-center button hidden
# Note: the first-run "choose interface style" / theme picker can NOT be
# suppressed via settings (it's UI state) — see vscode_seed_state for that.
# Note: workbench.secondarySideBar.defaultVisibility is deliberately NOT set
# here — its default is "visibleInWorkspace", which shows the right (secondary)
# sidebar on first launch when a folder is open AND the bar is non-empty (the
# seeded UI state docks Claude there, so it's non-empty). Setting it to
# "hidden" (as scheme C used to) is exactly what collapsed the right sidebar.
# Merges into any existing settings (python3 for safe JSON merge).
vscode_write_user_settings() {
  local settings; settings=$(vscode_user_settings_path)
  mkdir -p "$(dirname "$settings")"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$settings" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
data["workbench.startupEditor"] = "none"
data["workbench.welcomePage.walkthroughsVisible"] = False
data["update.showReleaseNotes"] = False
data["security.workspace.trust.enabled"] = False
data["claudeCode.initialPermissionMode"] = "acceptEdits"
data["claudeCode.preferredLocation"] = "sidebar"
data["claudeCode.disableLoginPrompt"] = True
data["claudeCode.hideOnboarding"] = True
data["chat.commandCenter.enabled"] = False
data["chat.disableAIFeatures"] = True
data["github.copilot.enable"] = {"*": False}
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  else
    cat > "$settings" <<'EOF'
{
  "workbench.startupEditor": "none",
  "workbench.welcomePage.walkthroughsVisible": false,
  "update.showReleaseNotes": false,
  "security.workspace.trust.enabled": false,
  "claudeCode.initialPermissionMode": "acceptEdits",
  "claudeCode.preferredLocation": "sidebar",
  "claudeCode.disableLoginPrompt": true,
  "claudeCode.hideOnboarding": true,
  "chat.commandCenter.enabled": false,
  "chat.disableAIFeatures": true,
  "github.copilot.enable": { "*": false }
}
EOF
  fi
  note "wrote VS Code user settings (skip welcome, trust on, Claude Code sidebar + skip login, Copilot off)"
}

# Seed the VS Code UI-state DB (state.vscdb) so a fresh install reproduces the
# captured golden state (see wip/golden-state-keys.md + wip/golden-state.vscdb):
#   - first-run flags (welcomeOnboarding.state, theme notification) suppress the
#     "choose interface style"/theme picker, which settings.json CANNOT suppress
#     (it's UI state, not a setting);
#   - the pinnedPanels + secondary-sidebar view-state keys dock the Claude Code
#     view in the RIGHT (secondary) sidebar, and auxiliaryBar.empty=false marks
#     the bar non-empty. Together with the default
#     workbench.secondarySideBar.defaultVisibility ("visibleInWorkspace", so
#     we do NOT set that setting), VS Code opens the right sidebar ON FIRST
#     LAUNCH with Claude Code in it (verified against workbench.desktop.main.js
#     AUXILIARYBAR_HIDDEN.defaultValue + the golden capture). THIS is what
#     places the plugin — the installer no longer auto-opens Claude Code via
#     the vscode://anthropic.claude-code/open URI, because that handler opens a
#     CENTER editor tab (primaryEditor.open) and ignores preferredLocation;
#   - the extension-global-state flags (Anthropic.claude-code) stop the
#     first-activation walkthrough from auto-opening in the editor and keep the
#     onboarding checklist off. Seeded INSERT OR IGNORE (fresh installs only) so
#     a re-run never clobbers the extension's own state.
# All keys are portable (booleans/JSON, no machine paths — verified against the
# golden template). Best-effort: needs python3 (system, or a python passed as
# $1). CREATE TABLE IF NOT EXISTS + INSERT merge into an existing DB; creates
# fresh if absent, so VS Code's first launch reads the
# seeded state.
vscode_seed_state() {
  local db; db=$(vscode_state_db_path)
  local py="${1:-}"
  if [ -z "$py" ]; then command -v python3 >/dev/null 2>&1 && py=python3; fi
  if [ -z "$py" ]; then warn "no python3 to seed VS Code UI state — first-run onboarding may show"; return 0; fi
  "$py" - "$db" <<'PY'
import sqlite3, os, sys
path = sys.argv[1]
os.makedirs(os.path.dirname(path), exist_ok=True)
con = sqlite3.connect(path)
con.execute("CREATE TABLE IF NOT EXISTS ItemTable (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB)")
# Written on every run (idempotent): first-run flags + Claude docked in the
# right (secondary) sidebar, shown on first launch -- values cut 1:1 from
# wip/golden-state.vscdb (auxiliaryBar.empty=false is what keeps the right
# sidebar from auto-collapsing).
seeds = {
    "welcomeOnboarding.state": "true",
    "workbench.newDefaultThemeNotification": "true",
    "workbench.auxiliarybar.pinnedPanels": '[{"id":"workbench.panel.chat","pinned":true,"visible":false,"order":1},{"id":"workbench.view.extension.claude-sidebar-secondary","pinned":true,"visible":false,"order":101}]',
    "workbench.view.extension.claude-sidebar-secondary.state.hidden": '[{"id":"claudeVSCodeSidebarSecondary","isHidden":false}]',
    "workbench.auxiliaryBar.empty": "false",
}
# Written only when absent (INSERT OR IGNORE beats the schema's REPLACE):
# Claude Code extension state -- lastClaudeLocationMigrated stops the
# first-activation walkthrough auto-open, tengu_vscode_onboarding:false hides
# the onboarding checklist (from the golden capture).
fresh = {
    "Anthropic.claude-code": '{"settingsMigrated20251024":true,"lastClaudeLocationMigrated":true,"experimentGates":{"tengu_vscode_onboarding":false}}',
}
cur = con.cursor()
for k, v in seeds.items():
    cur.execute("INSERT OR REPLACE INTO ItemTable (key, value) VALUES (?, ?)", (k, v))
for k, v in fresh.items():
    cur.execute("INSERT OR IGNORE INTO ItemTable (key, value) VALUES (?, ?)", (k, v))
con.commit(); con.close()
print("seeded %d VS Code UI-state keys (+%d fresh-only) into %s" % (len(seeds), len(fresh), path))
PY
  note "seeded VS Code UI-state (skip first-run onboarding; Claude Code docked + shown in the right sidebar)"
}
