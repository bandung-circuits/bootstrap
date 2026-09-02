#!/usr/bin/env bash
# workspace.sh — create the default AI workspace dir (~/ai-workspace) and seed
# it from templates/workspace. $DSH_HOME lives INSIDE the workspace so the whole
# environment is one copyable folder (same philosophy as the vscode scheme's
# .claude/). The launch scripts (start-dsh.*) point dsh at it.

WORKSPACE_DIR="${HOME}/ai-workspace"
export WORKSPACE_DIR

workspace_create() {
  if [ ! -d "$WORKSPACE_DIR" ]; then
    mkdir -p "$WORKSPACE_DIR"
    note "created workspace at $WORKSPACE_DIR"
  fi
  seed_file        "README.md"
  seed_file        ".gitignore"
  seed_file        "AGENTS.md"
  seed_file        "start-dsh.sh"
  seed_file        "start-dsh.cmd"
  seed_file        "start-dsh.ps1"
  # NEXT-STEPS.md is rendered (which provider to get the key from) — the
  # provider labels must be resolved first.
  provider_labels
  if render_file "${TEMPLATES_DIR}/NEXT-STEPS.md" "$WORKSPACE_DIR/NEXT-STEPS.md"; then
    note "wrote $WORKSPACE_DIR/NEXT-STEPS.md"
  fi
  # Launchers must be executable.
  [ -f "$WORKSPACE_DIR/start-dsh.sh" ] && chmod +x "$WORKSPACE_DIR/start-dsh.sh" 2>/dev/null || true
}

# Seed one static workspace template if absent (logs "kept" when present).
seed_file() { # <relative-path>
  local rel="$1"
  if copy_file "${TEMPLATES_DIR}/${rel}" "$WORKSPACE_DIR/$rel"; then
    note "seeded $WORKSPACE_DIR/$rel"
  else
    note "kept existing $WORKSPACE_DIR/$rel"
  fi
}

# Seed $DSH_HOME (~/ai-workspace/.dsh): provider settings (rendered), the
# machine-local API key env (rendered, mode 600), the home-level patch with the
# crawl4ai MCP row, and a .gitignore for harness internals.
dsh_home_create() {
  local home="${WORKSPACE_DIR}/.dsh"
  export DSH_HOME="$home"
  mkdir -p "$home"

  provider_labels
  if render_file "${TEMPLATES_DSH_HOME}/settings.yaml" "$home/settings.yaml"; then
    note "wrote $home/settings.yaml"
  else
    note "kept existing $home/settings.yaml"
  fi

  if render_file "${TEMPLATES_DSH_HOME}/.env" "$home/.env"; then
    chmod 600 "$home/.env"
    note "wrote $home/.env (API key env; mode 600)"
  else
    note "kept existing $home/.env"
  fi

  mcp_ensure_patch   # crawl4ai via the official mcp-client row

  copy_file "${TEMPLATES_DSH_HOME}/.gitignore" "$home/.gitignore" >/dev/null 2>&1 \
    && note "wrote $home/.gitignore" || true
}