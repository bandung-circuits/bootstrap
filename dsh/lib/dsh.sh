#!/usr/bin/env bash
# dsh.sh — install the DeepSeek Harness CLI (`dsh`) and its Node runtime.
#
# Version policy (dev preview — pin everything that can move):
#   - dsh:  pinned npm package  @deepseek-ai/dsh@0.1.1-rc.2
#   - Node: pinned major 24 (LTS), latest patch resolved from the nodejs.org
#     dist index at install time; engine requirement is ^22.19.0 || >=24.0.0.
#   - Node is installed to ~/.local/nodejs as the current user (no sudo), the
#     same dir this project's uv/uvx ~/.local/bin already uses; the
#     start-dsh.sh launcher prepends both to PATH.

DSH_NPM_PKG="${DSH_NPM_PKG:-@deepseek-ai/dsh@0.1.1-rc.2}"
NODE_MAJOR=24
NODE_PREFIX="${HOME}/.local/nodejs"
LOCAL_BIN="${HOME}/.local/bin"

# Node engine requirement from the official repo: ^22.19.0 || >=24.0.0
node_is_ok() {
  command -v node >/dev/null 2>&1 || return 1
  local v maj min
  v="$(node -v 2>/dev/null | tr -d 'v')" || return 1
  maj="${v%%.*}"; min="${v#*.}"; min="${min%%.*}"
  [ "$maj" -ge 24 ] && return 0
  [ "$maj" -eq 22 ] && [ "$min" -ge 19 ] && return 0
  return 1
}

# Resolve the latest v$NODE_MAJOR.x LTS from the official dist index (the JSON
# is newest-first). The lts field sits after several others inside each entry,
# so a naive "version right before lts" grep never matches — parse real JSON.
node_latest_lts() {
  local idx
  idx="$(curl -fsSL --max-time 30 https://nodejs.org/dist/index.json 2>/dev/null || \
         wget -qO- --timeout=30 https://nodejs.org/dist/index.json 2>/dev/null)" || return 1
  if command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "$idx" | python3 -c '
import json, sys
d = json.load(sys.stdin)
for e in d:
    v = e["version"]
    if v.startswith("v") and e.get("lts") and int(v.split(".")[0][1:]) == '"$NODE_MAJOR"':
        print(v[1:]); break
' | head -1
  else
    # sed fallback: first v-major entry that also declares an LTS codename.
    printf '%s\n' "$idx" \
      | sed -nE 's/.*"version":"v('"$NODE_MAJOR"'[0-9.]+)"[^}]*"lts":"[A-Z][A-Za-z]*".*/\1/p' \
      | head -1
  fi
}

# Install Node LTS for the current user under ~/.local/nodejs (no sudo).
node_install() {
  if node_is_ok; then
    note "Node $(node -v) present (>=22.19 required) — reusing it"
    return 0
  fi
  if [ -x "$NODE_PREFIX/bin/node" ] && node_is_ok "$NODE_PREFIX/bin/node" 2>/dev/null; then
    note "Node in $NODE_PREFIX is fine — adding to PATH"
    export PATH="$NODE_PREFIX/bin:$PATH"
    node_link_bin
    return 0
  fi
  local ver plat arch url
  ver="$(node_latest_lts)" || err "could not resolve the latest Node ${NODE_MAJOR}.x from nodejs.org"
  [ -n "$ver" ] || err "could not resolve the latest Node ${NODE_MAJOR}.x from nodejs.org (empty result)"
  plat=linux; [ "$DETECT_OS" = "macos" ] && plat=darwin
  arch=x64;  [ "$DETECT_ARCH" = "arm64" ] && arch=arm64
  url="https://nodejs.org/dist/v${ver}/node-v${ver}-${plat}-${arch}.tar.gz"
  note "installing Node v${ver} (${plat}/${arch}) into $NODE_PREFIX (no sudo)"
  mkdir -p "$NODE_PREFIX"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" | tar -xz -C "$NODE_PREFIX" --strip-components=1
  else
    wget -qO- "$url" | tar -xz -C "$NODE_PREFIX" --strip-components=1
  fi
  export PATH="$NODE_PREFIX/bin:$PATH"
  node_link_bin
  note "Node $(node -v) installed"
}

# Best-effort: link node/npm/npx/dsh into ~/.local/bin (uv already lands there).
node_link_bin() {
  [ -d "$LOCAL_BIN" ] || return 0
  for b in node npm npx; do
    [ -x "$NODE_PREFIX/bin/$b" ] && ln -sf "$NODE_PREFIX/bin/$b" "$LOCAL_BIN/$b" 2>/dev/null || true
  done
}

# Install the dsh CLI globally for the user (~/.local/bin/dsh). Uses --prefix so
# a machine with a root-owned npm prefix never prompts for sudo.
dsh_install() {
  if command -v dsh >/dev/null 2>&1; then
    note "dsh already installed ($(dsh --version 2>/dev/null | head -1 || echo 'version unknown'))"
    return 0
  fi
  [ -x "$NODE_PREFIX/bin/npm" ] && export PATH="$NODE_PREFIX/bin:$PATH"
  if ! command -v npm >/dev/null 2>&1; then
    err "npm not available after Node install; run again in a new terminal"
  fi
  note "installing dsh CLI: npm install -g --prefix $LOCAL_BIN $DSH_NPM_PKG"
  npm install -g --prefix "$LOCAL_BIN" "$DSH_NPM_PKG" || err "npm install -g $DSH_NPM_PKG failed"
  [ -x "$LOCAL_BIN/dsh" ] || [ -x "$(command -v dsh)" ] \
    || err "dsh installed but not found on PATH"
  export PATH="$LOCAL_BIN:$PATH"
  note "dsh $(dsh --version 2>/dev/null | head -1 || echo 'installed')"
}

# Confirm dsh bootstraps its web profile + our patch (config dump). Best-effort;
# the real UI boot is verified by CI or the user's first launch.
#
# Note: --dump-config composes the Cordis PATCH tree (bundle layers + the
# home-level cordis.patch.yml). The model provider route lives in the
# settings.yaml seam, which pi-ai reads per request — it is NOT a patch layer,
# so it never appears in the dump. Check it on the file instead.
dsh_smoke() {
  if [ "${BOOTSTRAP_SKIP_DUMP:-0}" = "1" ]; then return 0; fi
  local out
  note "dumping composed config (--dump-config) to confirm the MCP row"
  out="$(DSH_HOME="$DSH_HOME" dsh web --dump-config 2>&1 || true)"
  if printf '%s\n' "$out" | grep -q 'mcp-crawl4ai'; then
    note "config OK (mcp-crawl4ai MCP row present)"
  else
    warn "mcp-crawl4ai not found in --dump-config; check $DSH_HOME/cordis.patch.yml"
  fi
  if [ -f "$DSH_HOME/settings.yaml" ] && grep -q "baseURL: $PROVIDER_BASE_URL" "$DSH_HOME/settings.yaml"; then
    note "provider route OK ($PROVIDER_ID)"
  else
    warn "provider route missing in $DSH_HOME/settings.yaml"
  fi
}