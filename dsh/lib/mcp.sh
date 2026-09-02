#!/usr/bin/env bash
# mcp.sh — enable the crawl4ai MCP server through the OFFICIAL dsh MCP client
# (@deepseek-ai/dsh-mcp-client). The plugin ships with the dsh CLI, so no plugin
# install is needed: a row under `insert:` in the home-level
# $DSH_HOME/cordis.patch.yml (applies to every profile) mounts it. The row text
# lives in templates/dsh-home/ (single source of truth), not in this script.
#
# Server commands run OUTSIDE the agent sandbox, so only pinned, trusted
# executables are enabled here (uvx + the pinned crawl4ai-search-mcp package).

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