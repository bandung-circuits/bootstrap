#!/usr/bin/env bash
# config.sh — copy static templates into the workspace and $DSH_HOME, and
# render the placeholders. The templates directory is the single source of
# truth for every seeded file; the installer only copies/replaces — nothing is
# embedded in shell code. Never overwrites an existing file (re-runs keep user
# edits).

# Copy a template file to a destination if absent. Returns 0 if copied,
# 1 if the destination already existed.
copy_file() { # <src> <dst>
  local src="$1" dst="$2"
  [ -f "$dst" ] && return 1
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  return 0
}

# Render a template ({{PROVIDER_*}} / {{COMPAT_BLOCK}} / {{DSH_API_KEY}}
# placeholders) to a destination if absent. python3 when available, else sed.
# Returns 0 if written, 1 if the destination already existed.
render_file() { # <src> <dst>
  local src="$1" dst="$2"
  [ -f "$dst" ] && return 1
  mkdir -p "$(dirname "$dst")"
  if command -v python3 >/dev/null 2>&1; then
    PROVIDER_ID="$PROVIDER_ID" PROVIDER_BASE_URL="$PROVIDER_BASE_URL" \
    PROVIDER_MODEL="$PROVIDER_MODEL" PROVIDER_API="${PROVIDER_API:-}" \
    COMPAT_BLOCK="${COMPAT_BLOCK:-}" PROVIDER_NAME="${PROVIDER_NAME:-}" \
    PROVIDER_SITE="${PROVIDER_SITE:-}" DSH_API_KEY="${DSH_API_KEY:-}" \
    python3 - "$src" "$dst" <<'PY'
import os, sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
for k in ("PROVIDER_ID","PROVIDER_BASE_URL","PROVIDER_MODEL","PROVIDER_API",
          "COMPAT_BLOCK","PROVIDER_NAME","PROVIDER_SITE","DSH_API_KEY"):
    t = t.replace("{{%s}}" % k, os.environ.get(k, ""))
open(dst, "w", encoding="utf-8").write(t)
PY
  else
    sed -e "s|{{PROVIDER_ID}}|${PROVIDER_ID:-}|g" \
        -e "s|{{PROVIDER_BASE_URL}}|${PROVIDER_BASE_URL:-}|g" \
        -e "s|{{PROVIDER_MODEL}}|${PROVIDER_MODEL:-}|g" \
        -e "s|{{PROVIDER_API}}|${PROVIDER_API:-}|g" \
        -e "s|{{PROVIDER_NAME}}|${PROVIDER_NAME:-}|g" \
        -e "s|{{PROVIDER_SITE}}|${PROVIDER_SITE:-}|g" \
        -e "s|{{DSH_API_KEY}}|${DSH_API_KEY:-}|g" \
        -e "s|{{COMPAT_BLOCK}}|${COMPAT_BLOCK:-}|g" \
        "$src" > "$dst" || err "failed to render $dst"
  fi
  return 0
}