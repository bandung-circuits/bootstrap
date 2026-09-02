#!/usr/bin/env bash
# provider.sh — resolve provider from region/override, render the workspace
# settings from static templates.
# Sourced by install.sh.
#
# The workspace-seeding config files live as real template files under
# templates/workspace (single source of truth); the only thing this script does
# beyond provider resolution is substitute the provider values + API key into
# placeholders, then write the machine-local secret file.

# Resolve PROVIDER from region unless overridden by --provider.
# Sets: PROVIDER, PROVIDER_BASE_URL, PROVIDER_MODEL
provider_resolve() {
  if [ -z "${PROVIDER:-}" ]; then
    case "$DETECT_REGION" in
      china) PROVIDER=bailian ;;        # domestic Bailian (CN entity / Alipay)
      *)     PROVIDER=bailian-intl ;;  # Alibaba Cloud International (Visa/Mastercard)
    esac
  fi

  case "$PROVIDER" in
    bailian)        # domestic Bailian — tested with a real key
      PROVIDER_BASE_URL="https://dashscope.aliyuncs.com/apps/anthropic"
      PROVIDER_MODEL="deepseek-v4-flash-0731"
      ;;
    bailian-intl)  # Alibaba Cloud International (Model Studio), per alibabacloud.com docs
      PROVIDER_BASE_URL="https://dashscope-intl.aliyuncs.com/apps/anthropic"
      PROVIDER_MODEL="deepseek-v4-flash"
      ;;
    deepseek)      # DeepSeek official (fallback)
      PROVIDER_BASE_URL="https://api.deepseek.com/anthropic"
      PROVIDER_MODEL="deepseek-v4-flash"
      ;;
    openrouter)    # OpenRouter (fallback, wiring to be confirmed)
      PROVIDER_BASE_URL="https://openrouter.ai/api/v1"
      PROVIDER_MODEL="deepseek/deepseek-v4-flash"
      ;;
    *)
      err "unknown provider: $PROVIDER (use bailian|bailian-intl|deepseek|openrouter)"
      ;;
  esac
  export PROVIDER PROVIDER_BASE_URL PROVIDER_MODEL
}

# API key handling: if not passed via --api-key, write a placeholder. We do NOT
# prompt interactively — `curl|bash`/`wget|bash` pipe the script in, so stdin
# isn't a terminal and `read` would hit EOF and abort. The user pastes their key
# into settings.local.json after install (see NEXT-STEPS.md in the workspace).
# Sets: PROVIDER_API_KEY, PROVIDER_KEY_IS_PLACEHOLDER
provider_ensure_key() {
  if [ -n "${PROVIDER_API_KEY:-}" ]; then
    PROVIDER_KEY_IS_PLACEHOLDER=0
  else
    PROVIDER_API_KEY="PASTE-YOUR-API-KEY-HERE"
    PROVIDER_KEY_IS_PLACEHOLDER=1
  fi
  export PROVIDER_API_KEY PROVIDER_KEY_IS_PLACEHOLDER
}

provider_print() {
  printf '  Provider:  %s\n' "$PROVIDER"
  printf '  Base URL:  %s\n' "$PROVIDER_BASE_URL"
  printf '  Model:     %s\n' "$PROVIDER_MODEL"
}

# Render a template file to a destination, substituting {{ANTHROPIC_*}} and
# {{PROVIDER_NAME}}/{{PROVIDER_SITE}}/{{KEY_NOTICE}} placeholders. Never
# overwrites an existing file (re-runs keep user edits). Returns 0 if written,
# 1 if the destination already existed. Uses python3 when available, else sed.
render_template() { # <src> <dst>
  local src="$1" dst="$2"
  [ -f "$dst" ] && return 1
  mkdir -p "$(dirname "$dst")"
  if command -v python3 >/dev/null 2>&1; then
    ANTHROPIC_BASE_URL="$PROVIDER_BASE_URL" ANTHROPIC_AUTH_TOKEN="$PROVIDER_API_KEY" \
    ANTHROPIC_MODEL="$PROVIDER_MODEL" ANTHROPIC_EXTRA_ENV="${ANTHROPIC_EXTRA_ENV:-}" \
    PROVIDER_NAME="${PROVIDER_NAME:-}" PROVIDER_SITE="${PROVIDER_SITE:-}" KEY_NOTICE="${KEY_NOTICE:-}" \
    python3 - "$src" "$dst" <<'PY'
import os, sys
src, dst = sys.argv[1], sys.argv[2]
t = open(src, encoding="utf-8").read()
for k in ("ANTHROPIC_BASE_URL","ANTHROPIC_AUTH_TOKEN","ANTHROPIC_MODEL",
          "ANTHROPIC_EXTRA_ENV","PROVIDER_NAME","PROVIDER_SITE","KEY_NOTICE"):
    t = t.replace("{{%s}}" % k, os.environ.get(k, ""))
open(dst, "w", encoding="utf-8").write(t)
PY
  else
    sed -e "s|{{ANTHROPIC_BASE_URL}}|$PROVIDER_BASE_URL|g" \
        -e "s|{{ANTHROPIC_AUTH_TOKEN}}|$PROVIDER_API_KEY|g" \
        -e "s|{{ANTHROPIC_MODEL}}|$PROVIDER_MODEL|g" \
        -e "s|{{ANTHROPIC_EXTRA_ENV}}|${ANTHROPIC_EXTRA_ENV:-}|g" \
        -e "s|{{PROVIDER_NAME}}|${PROVIDER_NAME:-}|g" \
        -e "s|{{PROVIDER_SITE}}|${PROVIDER_SITE:-}|g" \
        -e "s|{{KEY_NOTICE}}|${KEY_NOTICE:-}|g" \
        "$src" > "$dst" || err "failed to render $dst"
  fi
}

# provider_write_settings — render ~/ai-workspace/.claude/settings.local.json
# from its template (gitignored: contains the API key).
provider_write_settings() {
  # Bailian / DashScope (domestic & intl) benefits from disabling server-side
  # data inspection. The template holds a prose JSON fragment on the previous
  # env line; when empty a trailing comma must not leak, so the fragment
  # carries its own leading comma.
  ANTHROPIC_EXTRA_ENV=""
  if [ "$PROVIDER" = "bailian" ] || [ "$PROVIDER" = "bailian-intl" ]; then
    # JSON fragment injected right after the "API_TIMEOUT_MS" line; carries its
    # own leading comma so the template stays valid when the entry is absent.
    ANTHROPIC_EXTRA_ENV=$',\n    "ANTHROPIC_CUSTOM_HEADERS": "X-DashScope-DataInspection: {\\"input\\":\\"disable\\",\\"output\\":\\"disable\\"}"'
  fi
  if render_template "${TEMPLATES_DIR}/settings.local.json.template" "${WORKSPACE_DIR}/.claude/settings.local.json"; then
    chmod 600 "${WORKSPACE_DIR}/.claude/settings.local.json" 2>/dev/null || true
    note "wrote ${WORKSPACE_DIR}/.claude/settings.local.json"
  else
    note "kept existing ${WORKSPACE_DIR}/.claude/settings.local.json"
  fi
}

# provider_write_next_steps — render ~/ai-workspace/NEXT-STEPS.md from its
# template (which provider to get the key from depends on the route).
provider_write_next_steps() {
  case "$PROVIDER" in
    bailian)       PROVIDER_NAME="Alibaba Cloud Bailian (China)";                  PROVIDER_SITE="https://bailian.console.aliyun.com/" ;;
    bailian-intl)  PROVIDER_NAME="Alibaba Cloud Model Studio (international)";     PROVIDER_SITE="https://dashscope-intl.console.aliyun.com/" ;;
    deepseek)      PROVIDER_NAME="DeepSeek";                                      PROVIDER_SITE="https://platform.deepseek.com/" ;;
    openrouter)    PROVIDER_NAME="OpenRouter";                                    PROVIDER_SITE="https://openrouter.ai/" ;;
  esac
  KEY_NOTICE=""
  if [ "${PROVIDER_KEY_IS_PLACEHOLDER:-0}" = "1" ]; then
    KEY_NOTICE=" (Note: an API key was already provided to the installer — you may skip this step if that key is the one you intend to use.)"
  fi
  mkdir -p "$WORKSPACE_DIR"
  local dst="$WORKSPACE_DIR/NEXT-STEPS.md"
  if render_template "${TEMPLATES_DIR}/NEXT-STEPS.md" "$dst"; then
    note "wrote $dst"
  else
    note "kept existing $dst"
  fi
}