#!/usr/bin/env bash
# providers.sh — resolve provider from region/override, then the DeepSeek
# Harness model-route fields (a pi-ai custom provider route in
# $DSH_HOME/settings.yaml). Region heuristics + base URLs are shared with the
# vscode scheme (lib/detect.sh); the dsh surface adds `api` (wire protocol) and
# an optional `compat` block for gateways pi-ai does not recognize.

# Resolve PROVIDER from region unless overridden by --provider.
# Sets: PROVIDER, PROVIDER_ID, PROVIDER_BASE_URL, PROVIDER_MODEL,
#       PROVIDER_API, COMPAT_BLOCK
provider_resolve() {
  if [ -z "${PROVIDER:-}" ]; then
    case "$DETECT_REGION" in
      china) PROVIDER=bailian ;;        # domestic Bailian (CN entity / Alipay)
      *)     PROVIDER=bailian-intl ;;  # Alibaba Cloud International (Visa/Mastercard)
    esac
  fi

  COMPAT_BLOCK=""
  case "$PROVIDER" in
    bailian)        # domestic Bailian — Anthropic-compatible endpoint
      PROVIDER_ID="bailian"
      PROVIDER_BASE_URL="https://dashscope.aliyuncs.com/apps/anthropic"
      PROVIDER_MODEL="deepseek-v4-flash-0731"
      PROVIDER_API="anthropic"
      ;;
    bailian-intl)  # Alibaba Cloud International (Model Studio)
      PROVIDER_ID="bailian-intl"
      PROVIDER_BASE_URL="https://dashscope-intl.aliyuncs.com/apps/anthropic"
      PROVIDER_MODEL="deepseek-v4-flash"
      PROVIDER_API="anthropic"
      ;;
    deepseek)      # DeepSeek official — native Anthropic-compatible endpoint
      PROVIDER_ID="deepseek"
      PROVIDER_BASE_URL="https://api.deepseek.com/anthropic"
      PROVIDER_MODEL="deepseek-v4-flash"
      PROVIDER_API="anthropic"
      ;;
    openrouter)    # OpenRouter — plain OpenAI-compatible endpoint
      PROVIDER_ID="openrouter"
      PROVIDER_BASE_URL="https://openrouter.ai/api/v1"
      PROVIDER_MODEL="deepseek/deepseek-v4-flash"
      PROVIDER_API="openai-completions"
      # OpenAI-compatible gateways often reject the developer role and only
      # know max_tokens; the official troubleshooting escape hatch for them.
      COMPAT_BLOCK=$'      compat:\n        supportsDeveloperRole: false\n        maxTokensField: max_tokens'
      ;;
    *)
      err "unknown provider: $PROVIDER (use bailian|bailian-intl|deepseek|openrouter)"
      ;;
  esac
  export PROVIDER PROVIDER_ID PROVIDER_BASE_URL PROVIDER_MODEL PROVIDER_API COMPAT_BLOCK
}

# API key handling: if not passed via --api-key, write a placeholder. We do NOT
# prompt interactively — `curl|bash`/`wget|bash` pipe the script in, so stdin
# isn't a terminal and `read` would hit EOF and abort. The user replaces the key
# in $DSH_HOME/.env after install (see NEXT-STEPS.md), or pastes it into the
# Web UI (Settings → Models).
# Sets: DSH_API_KEY, PROVIDER_KEY_IS_PLACEHOLDER
provider_ensure_key() {
  if [ -n "${DSH_API_KEY:-}" ]; then
    PROVIDER_KEY_IS_PLACEHOLDER=0
  else
    DSH_API_KEY="PASTE-YOUR-API-KEY-HERE"
    PROVIDER_KEY_IS_PLACEHOLDER=1
  fi
  export DSH_API_KEY PROVIDER_KEY_IS_PLACEHOLDER
}

provider_print() {
  printf '  Provider:  %s\n' "$PROVIDER_ID"
  printf '  Base URL:  %s\n' "$PROVIDER_BASE_URL"
  printf '  Model:     %s\n' "$PROVIDER_MODEL"
  printf '  API:       %s\n' "$PROVIDER_API"
}

# Human-facing provider labels for NEXT-STEPS.md.
# Sets: PROVIDER_NAME, PROVIDER_SITE
provider_labels() {
  case "$PROVIDER" in
    bailian)      PROVIDER_NAME="Alibaba Cloud Bailian (China)";            PROVIDER_SITE="https://bailian.console.aliyun.com/" ;;
    bailian-intl) PROVIDER_NAME="Alibaba Cloud Model Studio (international)"; PROVIDER_SITE="https://dashscope-intl.console.aliyun.com/" ;;
    deepseek)     PROVIDER_NAME="DeepSeek";                                PROVIDER_SITE="https://platform.deepseek.com/" ;;
    openrouter)   PROVIDER_NAME="OpenRouter";                              PROVIDER_SITE="https://openrouter.ai/" ;;
  esac
  export PROVIDER_NAME PROVIDER_SITE
}