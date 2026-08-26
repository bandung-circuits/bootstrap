#!/usr/bin/env bash
# crawl4ai.sh — install crawl4ai MCP server and register it in ~/.claude/.mcp.json.
# Free, no API key needed. Forked from gigix/crawl4ai-mcp-server.

CRAWL4AI_REPO="https://github.com/gigix/crawl4ai-mcp-server.git"
CRAWL4AI_DIR="${HOME}/.bootstrap/crawl4ai-mcp-server"

crawl4ai_is_installed() {
  [ -x "$CRAWL4AI_DIR/venv/bin/python" ] && [ -f "$CRAWL4AI_DIR/src/index.py" ]
}

crawl4ai_install() {
  if crawl4ai_is_installed; then note "crawl4ai MCP already installed at $CRAWL4AI_DIR"; return 0; fi

  command -v git    >/dev/null 2>&1 || err "git not found; install git first"
  command -v python3 >/dev/null 2>&1 || err "python3 not found; install python3 first"

  mkdir -p "$(dirname "$CRAWL4AI_DIR")"
  note "cloning crawl4ai-mcp-server"
  if [ ! -d "$CRAWL4AI_DIR" ]; then
    git clone --depth 1 "$CRAWL4AI_REPO" "$CRAWL4AI_DIR" || err "git clone failed"
  fi

  note "creating venv"
  python3 -m venv "$CRAWL4AI_DIR/venv" || err "venv creation failed"
  note "installing dependencies (this can take a minute)"
  "$CRAWL4AI_DIR/venv/bin/pip" install --upgrade pip -q
  "$CRAWL4AI_DIR/venv/bin/pip" install -r "$CRAWL4AI_DIR/requirements.txt" -q \
    || err "pip install failed"

  crawl4ai_register_mcp
}

# Merge crawl4ai entry into ~/.claude/.mcp.json (python3 for safe JSON merge).
crawl4ai_register_mcp() {
  local mcp_dir="${HOME}/.claude"
  local mcp_file="$mcp_dir/.mcp.json"
  mkdir -p "$mcp_dir"

  local py_bin="$CRAWL4AI_DIR/venv/bin/python"
  [ "$DETECT_OS" = "windows" ] && py_bin="$CRAWL4AI_DIR/venv/Scripts/python.exe"

  python3 - "$mcp_file" "$CRAWL4AI_DIR" "$py_bin" <<'PY'
import json, os, sys
path, srvdir, pybin = sys.argv[1:4]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
servers = data.setdefault("mcpServers", {})
# Refresh path each run in case of reinstall/move.
servers["crawl4ai"] = {
    "command": pybin,
    "args": [os.path.join(srvdir, "src", "index.py")],
    "cwd": srvdir,
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  chmod 600 "$mcp_file"
  note "registered crawl4ai in $mcp_file"
}

crawl4ai_postinstall_hint() {
  cat <<'MSG'

  crawl4ai note: the first time Claude Code calls crawl4ai, it will download
  a headless browser (Playwright/Chromium). This is automatic but needs
  network access and may take a minute. No API key is required.
MSG
}
