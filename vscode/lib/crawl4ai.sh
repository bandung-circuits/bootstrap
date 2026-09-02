#!/usr/bin/env bash
# crawl4ai.sh — register the crawl4ai MCP server in the workspace .mcp.json.
# Free, no API key needed. The server runs from the published
# `crawl4ai-search-mcp` package via uvx — the same invocation the maintainer
# uses (see the top-level .mcp.json):
#     uvx --from crawl4ai-search-mcp==0.1.1 crawl4ai-search
# uvx ships with uv (installed below if missing); on first use it fetches a
# prebuilt environment, so there is nothing to clone or build locally.

CRAWL4AI_PKG="crawl4ai-search-mcp==0.1.1"
UV_DIR="${HOME}/.local/bin"
UV_BIN="${UV_DIR}/uv"

# Install uv (single binary) if not present; uvx comes bundled with it.
ensure_uv() {
  [ -x "$UV_BIN" ] && return 0
  note "installing uv (Python package/runtime manager; provides uvx)"
  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  else
    wget -qO- https://astral.sh/uv/install.sh | sh
  fi
  [ -x "$UV_BIN" ] || err "uv install failed"
}

crawl4ai_is_installed() {
  # Already registered as the uvx entry in the workspace .mcp.json?
  local mcp_file="${WORKSPACE_DIR}/.mcp.json"
  [ -f "$mcp_file" ] && grep -q "$CRAWL4AI_PKG" "$mcp_file"
}

crawl4ai_install() {
  if crawl4ai_is_installed; then note "crawl4ai MCP already registered in ${WORKSPACE_DIR}/.mcp.json"; return 0; fi
  ensure_uv
  crawl4ai_register_mcp
}

# Register crawl4ai in the WORKSPACE's .mcp.json (project scope, self-contained —
# config travels with the workspace; .mcp.json has no secrets so it can be committed).
crawl4ai_register_mcp() {
  local mcp_file="${WORKSPACE_DIR}/.mcp.json"
  mkdir -p "$WORKSPACE_DIR"

  # System python3 (any version) is fine for JSON merge — no deps needed.
  python3 - "$mcp_file" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
servers = data.setdefault("mcpServers", {})
servers["crawl4ai"] = {
    "command": "uvx",
    "args": ["--from", "crawl4ai-search-mcp==0.1.1", "crawl4ai-search"],
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  note "registered crawl4ai (uvx) in $mcp_file"
}

crawl4ai_postinstall_hint() {
  cat <<'MSG'

  crawl4ai note: the first time Claude Code calls crawl4ai, uvx will pull down
  the crawl4ai-search-mcp environment, and a headless browser (Playwright) may
  be downloaded too. This is automatic but needs network access and may take a
  minute. No API key is required.
MSG
}
