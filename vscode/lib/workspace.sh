#!/usr/bin/env bash
# workspace.sh — create the default AI workspace dir and seed it from the static
# templates/workspace tree, then open VS Code there.
#
# Every seeded file (README.md, .gitignore, .vscode/settings.json, CLAUDE.md)
# is a real file under templates/workspace — nothing is embedded in this script.
# The installer only copies templates in; provider.sh renders the key-bearing
# settings.local.json / NEXT-STEPS.md from their own templates.

WORKSPACE_DIR="${HOME}/ai-workspace"

# Copy one template leaf into the workspace if absent, optionally under a
# different installed name. Never overwrites an existing file, so re-running
# the installer keeps user edits.
workspace_seed_file() { # <templates-relative-path> [installed-name]
  local rel="$1" name="${2:-$1}"
  local src="${TEMPLATES_DIR}/${rel}"
  local dst="${WORKSPACE_DIR}/${name}"
  [ -f "$dst" ] && return 0
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  note "seeded $dst"
}

workspace_create() {
  if [ ! -d "$WORKSPACE_DIR" ]; then
    mkdir -p "$WORKSPACE_DIR"
    note "created workspace at $WORKSPACE_DIR"
  fi

  workspace_seed_file "README.md"
  workspace_seed_file "_gitignore" ".gitignore"
  # workspace .vscode/settings.json — mirror the Claude Code / Copilot settings
  # (belt; user settings are the authoritative place, but this covers the case
  # of a user who later wipes their user settings). No
  # workbench.secondarySideBar.defaultVisibility here: its default
  # ("visibleInWorkspace") + the seeded UI state show the right sidebar with
  # Claude Code on first launch.
  workspace_seed_file ".vscode/settings.json"
  # default CLAUDE.md — workspace rules for Claude Code (web-tool priority +
  # grounded search + backend)
  workspace_seed_file "CLAUDE.md"
}

# Open VS Code in the workspace with NEXT-STEPS.md open. Opening the folder
# (not just the file) makes VS Code load .claude/settings.local.json, .mcp.json,
# and .vscode/settings.json; opening the file too puts the user's next step
# (add the API key) right in front of them.
#
# Deliberately does NOT auto-open the Claude Code panel via the
# vscode://anthropic.claude-code/open URI. That handler resolves to the
# extension's `primaryEditor.open` command, which opens a NEW TAB in the CENTER
# editor area and ignores claudeCode.preferredLocation (verified in
# anthropic.claude-code v2.1.247 extension.js, in the official docs — the docs
# describe the URI as "open a new Claude Code tab" — and upstream issue
# anthropics/claude-code#89511). The panel's position comes from the seeded
# UI state instead: vscode_seed_state docks the Claude view in the right
# (secondary) sidebar from the captured golden state, and
# claudeCode.preferredLocation=sidebar in settings keeps every normal "Open"
# (Spark icon, status-bar "Claude Code", Cmd+Shift+Esc) in the right sidebar.
# The user opens it with the Spark icon (top-right) — it lands on the right.
workspace_open() {
  # CI runs the installer over SSH with no desktop session; launching `code`
  # (a GUI) there spins and can freeze the VM so hard that vmrun can't stop
  # it. Real users run the installer in a desktop terminal, where launching
  # is the point. run-test.sh sets BOOTSTRAP_NO_LAUNCH=1 to skip here.
  if [ "${BOOTSTRAP_NO_LAUNCH:-0}" = "1" ]; then
    note "skipping VS Code launch (BOOTSTRAP_NO_LAUNCH=1)"
    return
  fi
  if command -v code >/dev/null 2>&1; then
    note "opening VS Code in $WORKSPACE_DIR (NEXT-STEPS.md; Claude Code opens in the right sidebar)"
    code "$WORKSPACE_DIR" "$WORKSPACE_DIR/NEXT-STEPS.md" >/dev/null 2>&1 \
      || warn "could not open VS Code automatically; run: code $WORKSPACE_DIR"
  else
    warn "open VS Code manually in: $WORKSPACE_DIR"
  fi
}