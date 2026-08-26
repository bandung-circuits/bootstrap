#!/usr/bin/env bash
# crawl4ai.sh — install crawl4ai MCP server and register it in the workspace .mcp.json.
# Free, no API key needed. Uses uv to provision a pinned Python (3.10) so the deps
# (lxml / pillow / pydantic-core) get prebuilt wheels — system Python may be too new
# (e.g. 3.14) and force fragile source builds. Forked from gigix/crawl4ai-mcp-server.

CRAWL4AI_REPO="https://github.com/gigix/crawl4ai-mcp-server.git"
# Branch with the ddgs migration fix (the version the maintainer actually uses);
# main still uses the deprecated duckduckgo_search and is broken.
CRAWL4AI_BRANCH="fix/migrate-to-ddgs-library"
CRAWL4AI_DIR="${HOME}/.bootstrap/crawl4ai-mcp-server"
# Python version with prebuilt wheels for all crawl4ai deps.
CRAWL4AI_PY="3.10"
UV_DIR="${HOME}/.local/bin"
UV_BIN="${UV_DIR}/uv"

crawl4ai_is_installed() {
  [ -x "$CRAWL4AI_DIR/venv/bin/python" ] && [ -f "$CRAWL4AI_DIR/src/index.py" ]
}

ensure_base_tools() {
  local need=""
  command -v git  >/dev/null 2>&1 || need="$need git"
  command -v curl >/dev/null 2>&1 || need="$need curl"
  [ -z "$need" ] && return 0
  note "installing base tools:$need"
  case "$DETECT_OS" in
    linux|wsl)
      case "$DETECT_PKG_MANAGER" in
        apt)   sudo apt-get update -y && sudo apt-get install -y$need ;;
        dnf)   sudo dnf install -y$need ;;
        yum)   sudo yum install -y$need ;;
        pacman) sudo pacman -S --noconfirm $need ;;
        *) err "missing base tools and no supported package manager" ;;
      esac ;;
    macos) brew install$need ;;
    *) err "git/curl missing; install manually" ;;
  esac
}

# Install uv (single binary) if not present.
ensure_uv() {
  [ -x "$UV_BIN" ] && return 0
  note "installing uv (Python package/runtime manager)"
  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  else
    wget -qO- https://astral.sh/uv/install.sh | sh
  fi
  [ -x "$UV_BIN" ] || err "uv install failed"
}

crawl4ai_install() {
  if crawl4ai_is_installed; then note "crawl4ai MCP already installed at $CRAWL4AI_DIR"; return 0; fi

  ensure_base_tools
  ensure_uv

  mkdir -p "$(dirname "$CRAWL4AI_DIR")"
  note "cloning crawl4ai-mcp-server (branch $CRAWL4AI_BRANCH)"
  if [ ! -d "$CRAWL4AI_DIR" ]; then
    git clone --branch "$CRAWL4AI_BRANCH" --depth 1 "$CRAWL4AI_REPO" "$CRAWL4AI_DIR" || err "git clone failed"
  fi

  note "provisioning Python $CRAWL4AI_PY via uv (prebuilt wheels for deps)"
  "$UV_BIN" python install "$CRAWL4AI_PY" >/dev/null 2>&1 || err "uv python install failed"
  note "creating venv (Python $CRAWL4AI_PY)"
  "$UV_BIN" venv --python "$CRAWL4AI_PY" "$CRAWL4AI_DIR/venv" || err "venv creation failed"
  note "installing dependencies via uv (prebuilt wheels; may take a minute)"
  "$UV_BIN" pip install --python "$CRAWL4AI_DIR/venv/bin/python" -r "$CRAWL4AI_DIR/requirements.txt" \
    || err "pip install failed"

  crawl4ai_register_mcp
}

# Register crawl4ai in the WORKSPACE's .mcp.json (project scope, self-contained —
# config travels with the workspace; .mcp.json has no secrets so it can be committed).
crawl4ai_register_mcp() {
  local mcp_file="${WORKSPACE_DIR}/.mcp.json"
  mkdir -p "$WORKSPACE_DIR"

  local py_bin="$CRAWL4AI_DIR/venv/bin/python"
  [ "$DETECT_OS" = "windows" ] && py_bin="$CRAWL4AI_DIR/venv/Scripts/python.exe"

  # System python3 (any version) is fine for JSON merge — no deps needed.
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
