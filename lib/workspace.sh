#!/usr/bin/env bash
# workspace.sh — create a default AI workspace dir and seed it, then open VS Code there.

WORKSPACE_DIR="${HOME}/ai-workspace"

workspace_create() {
  if [ ! -d "$WORKSPACE_DIR" ]; then
    mkdir -p "$WORKSPACE_DIR"
    note "created workspace at $WORKSPACE_DIR"
  fi

  local readme="$WORKSPACE_DIR/README.md"
  if [ ! -f "$readme" ]; then
    cat > "$readme" <<'MD'
# My AI workspace

This folder is your default workspace for Claude Code. Keep your projects here.

## Quick start

1. Open this folder in VS Code.
2. The Claude Code panel is docked in the sidebar (right) and opens with VS Code. It never opens in the center editor tab by itself.
3. Tell the AI what you want, e.g.:
   - "create a hello.py and run it"
   - "find recent news about <topic> and save it to news.md"
   - "explain what's in this folder"

The backend is DeepSeek V4 Flash 0731. The crawl4ai MCP (web fetch/search) is ready.
MD
    note "seeded $readme"
  fi

  # a per-user gitignore so AI-generated artifacts don't pollute
  if [ ! -f "$WORKSPACE_DIR/.gitignore" ]; then
    cat > "$WORKSPACE_DIR/.gitignore" <<'GI'
node_modules/
.venv/
venv/
__pycache__/
*.log
.DS_Store
# settings.local.json contains your API key — keep it in the folder, out of git.
.claude/settings.local.json
GI
  fi

  # workspace .vscode/settings.json — mirror the Claude Code / Copilot settings
  # (belt; user settings are the authoritative place, but this covers the case
  # of a user who later wipes their user settings). No
  # workbench.secondarySideBar.defaultVisibility here: its default
  # ("visibleInWorkspace") + the seeded UI state show the right sidebar with
  # Claude Code on first launch.
  local vscode_dir="$WORKSPACE_DIR/.vscode"
  if [ ! -f "$vscode_dir/settings.json" ]; then
    mkdir -p "$vscode_dir"
    cat > "$vscode_dir/settings.json" <<'VSC'
{
  "claudeCode.preferredLocation": "sidebar",
  "claudeCode.disableLoginPrompt": true,
  "claudeCode.hideOnboarding": true,
  "chat.commandCenter.enabled": false,
  "chat.disableAIFeatures": true,
  "github.copilot.enable": { "*": false }
}
VSC
    note "seeded $vscode_dir/settings.json"
  fi

  # default CLAUDE.md — workspace rules for Claude Code (web-tool priority + grounded search)
  if [ ! -f "$WORKSPACE_DIR/CLAUDE.md" ]; then
    cat > "$WORKSPACE_DIR/CLAUDE.md" <<'MD'
# CLAUDE.md — workspace rules for Claude Code

## Web tools: prefer crawl4ai
When you need to read a web page or search the web, prefer the crawl4ai MCP
(`mcp__crawl4ai__read_url` to fetch a page, `mcp__crawl4ai__search` to search).
It is free and needs no API key. If crawl4ai is unavailable for some reason,
fall back to WebFetch / WebSearch.

## Grounded search (avoid hallucination)
When you search the web, never trust a search summary alone. Fetch the real web
page (or PDF) in full with `mcp__crawl4ai__read_url` and read its actual content
before you answer. Cite the source URL in your reply.

## Backend
This workspace talks to DeepSeek V4 Flash 0731 through the provider configured in
`.claude/settings.local.json` (where you pasted your API key). No Anthropic sign-in
is needed.
MD
    note "seeded $WORKSPACE_DIR/CLAUDE.md"
  fi
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
