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
2. Open the Claude Code panel (sidebar).
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

# Open VS Code in the workspace (best-effort; don't fail the install if it can't).
workspace_open() {
  if command -v code >/dev/null 2>&1; then
    note "opening VS Code in $WORKSPACE_DIR"
    code "$WORKSPACE_DIR" >/dev/null 2>&1 || warn "could not open VS Code automatically; run: code $WORKSPACE_DIR"
  else
    warn "open VS Code manually in: $WORKSPACE_DIR"
  fi
}
