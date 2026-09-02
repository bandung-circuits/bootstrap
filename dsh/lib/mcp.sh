#!/usr/bin/env bash
# mcp.sh — enable the crawl4ai MCP server through the OFFICIAL dsh MCP client
# (@deepseek-ai/dsh-mcp-client). The plugin ships with the dsh CLI, so no plugin
# install is needed: a row under `insert:` in the home-level
# $DSH_HOME/cordis.patch.yml (applies to every profile) mounts it. The row text
# lives in templates/dsh-home/ (single source of truth), not in this script.
#
# Server commands run OUTSIDE the agent sandbox, so only pinned, trusted
# executables are enabled here (uvx + the pinned crawl4ai-search-mcp package).
# uv/uvx are therefore installed as part of the bootstrap (no key needed).

UV_DIR="${HOME}/.local/bin"
UV_BIN="${UV_DIR}/uv"

# Install uv (single binary) if not present; uvx comes bundled with it.
ensure_uv() {
  [ -x "$UV_BIN" ] && { export PATH="$UV_DIR:$PATH"; return 0; }
  note "installing uv (Python package/runtime manager; provides uvx)"
  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  else
    wget -qO- https://astral.sh/uv/install.sh | sh
  fi
  [ -x "$UV_BIN" ] || err "uv install failed"
  export PATH="$UV_DIR:$PATH"
  note "uv $(uv --version 2>/dev/null || echo installed)"
}

# Warm the uvx cache for the crawl4ai MCP package so the harness's first spawn
# is fast. Best-effort (a slow network just skips; the MCP still works on first
# call). Also pulls the Playwright Chromium browser if missing.
crawl4ai_warm() {
  command -v uvx >/dev/null 2>&1 || return 0
  local uvx_bin=uvx
  [ -x "$UV_DIR/uvx" ] && uvx_bin="$UV_DIR/uvx"
  ( timeout 420 "$uvx_bin" --from crawl4ai-search-mcp==0.1.1 python -c 'import crawl4ai_mcp_server' >/dev/null 2>&1 \
    && timeout 420 "$uvx_bin" --from crawl4ai-search-mcp==0.1.1 python -c 'from playwright.sync_api import sync_playwright; p=sync_playwright().start(); b=p.chromium.launch(); b.close(); p.stop()' >/dev/null 2>&1 ) \
    && note "crawl4ai runtime warmed" || return 1
}

mcp_ensure_patch() {
  local patch="$DSH_HOME/cordis.patch.yml"
  local full_template="${TEMPLATES_DSH_HOME}/cordis.patch.yml"
  local row_template="${TEMPLATES_DSH_HOME}/crawl4ai-row.yml"

  if [ ! -f "$patch" ]; then
    cp "$full_template" "$patch"
    note "enabled crawl4ai MCP in $patch"
    return 0
  fi
  if grep -q "mcp-crawl4ai" "$patch"; then
    note "crawl4ai MCP already enabled in $patch"
    return 0
  fi
  # Existing custom patch without crawl4ai: append the canonical row (a second
  # `- insert:` block — multiple inserts are valid).
  cat "$row_template" >> "$patch"
  note "appended crawl4ai MCP row to $patch"
}