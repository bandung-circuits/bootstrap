#!/usr/bin/env bash
# crawl4ai.sh — install crawl4ai MCP server and register it in ~/.claude/.mcp.json.
# Free, no API key needed. Forked from gigix/crawl4ai-mcp-server.

CRAWL4AI_REPO="https://github.com/gigix/crawl4ai-mcp-server.git"
# Branch with the ddgs migration fix (the version the maintainer actually uses);
# main still uses the deprecated duckduckgo_search and is broken.
CRAWL4AI_BRANCH="fix/migrate-to-ddgs-library"
CRAWL4AI_DIR="${HOME}/.bootstrap/crawl4ai-mcp-server"

crawl4ai_is_installed() {
  [ -x "$CRAWL4AI_DIR/venv/bin/python" ] && [ -f "$CRAWL4AI_DIR/src/index.py" ]
}

crawl4ai_install() {
  if crawl4ai_is_installed; then note "crawl4ai MCP already installed at $CRAWL4AI_DIR"; return 0; fi

  # ensure git + python3 are present (python3 is also required for the venv)
  ensure_base_tools

  mkdir -p "$(dirname "$CRAWL4AI_DIR")"
  note "cloning crawl4ai-mcp-server (branch $CRAWL4AI_BRANCH)"
  if [ ! -d "$CRAWL4AI_DIR" ]; then
    git clone --branch "$CRAWL4AI_BRANCH" --depth 1 "$CRAWL4AI_REPO" "$CRAWL4AI_DIR" || err "git clone failed"
  fi

  note "creating venv"
  python3 -m venv "$CRAWL4AI_DIR/venv" || err "venv creation failed"
  note "installing dependencies (this can take a minute)"
  "$CRAWL4AI_DIR/venv/bin/pip" install --upgrade pip -q
  "$CRAWL4AI_DIR/venv/bin/pip" install -r "$CRAWL4AI_DIR/requirements.txt" -q \
    || err "pip install failed"

  crawl4ai_register_mcp
}

# Install git + python3 if missing, using the detected package manager.
ensure_base_tools() {
  local need=""
  command -v git     >/dev/null 2>&1 || need="$need git"
  command -v python3 >/dev/null 2>&1 || need="$need python3"
  [ -z "$need" ] && need_set=0 || need_set=1
  # On Debian/Ubuntu, python3-venv (ensurepip wheels) is a separate package and
  # `import ensurepip` lies (imports fine without the wheels). Always ensure it.
  if [ "$DETECT_OS" = "linux" ] && [ "$DETECT_PKG_MANAGER" = "apt" ]; then
    need="$need python3-venv"; need_set=1
  fi
  [ "$need_set" -eq 1 ] || return 0
  note "installing base tools:$need"
  case "$DETECT_OS" in
    linux|wsl)
      case "$DETECT_PKG_MANAGER" in
        apt)
          # build deps for C-extension wheels (lxml has no wheel on very new Python)
          sudo apt-get update -y
          sudo apt-get install -y$need build-essential libxml2-dev libxslt-dev python3-dev
          ;;
        dnf)   sudo dnf install -y$need ;;
        yum)   sudo yum install -y$need ;;
        pacman) sudo pacman -S --noconfirm $need ;;
        *) err "git/python3 missing and no supported package manager" ;;
      esac ;;
    macos) brew install$need ;;
    *) err "git/python3 missing; install manually" ;;
  esac
}

# Register crawl4ai in the WORKSPACE's .mcp.json (project scope, self-contained —
# config travels with the workspace; .mcp.json has no secrets so it can be committed).
crawl4ai_register_mcp() {
  local mcp_file="${WORKSPACE_DIR}/.mcp.json"
  mkdir -p "$WORKSPACE_DIR"

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
servers["crawl4ai"] = {
    "command": pybin,
    "args": [os.path.join(srvdir, "src", "index.py")],
    "cwd": srvdir,
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  note "registered crawl4ai in $mcp_file"
}

crawl4ai_postinstall_hint() {
  cat <<'MSG'

  crawl4ai note: the first time Claude Code calls crawl4ai, it will download
  a headless browser (Playwright/Chromium). This is automatic but needs
  network access and may take a minute. No API key is required.
MSG
}
