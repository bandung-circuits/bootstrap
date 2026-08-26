#!/usr/bin/env bash
# provider.sh — resolve provider from region/override, build settings.json env block.
# Sourced by install.sh.

# Resolve PROVIDER from region unless overridden by --provider.
# Sets: PROVIDER, PROVIDER_BASE_URL, PROVIDER_MODEL
provider_resolve() {
  if [ -z "${PROVIDER:-}" ]; then
    case "$DETECT_REGION" in
      china) PROVIDER=bailian ;;
      *)     PROVIDER=deepseek ;;
    esac
  fi

  case "$PROVIDER" in
    bailian)
      PROVIDER_BASE_URL="https://dashscope.aliyuncs.com/apps/anthropic"
      PROVIDER_MODEL="deepseek-v4-flash-0731"
      ;;
    deepseek)
      PROVIDER_BASE_URL="https://api.deepseek.com/anthropic"
      PROVIDER_MODEL="deepseek-v4-flash"
      ;;
    openrouter)
      PROVIDER_BASE_URL="https://openrouter.ai/api/v1"
      PROVIDER_MODEL="deepseek/deepseek-v4-flash"
      ;;
    *)
      err "unknown provider: $PROVIDER (use bailian|deepseek|openrouter)"
      ;;
  esac
  export PROVIDER PROVIDER_BASE_URL PROVIDER_MODEL
}

# Ensure we have an API key. If not provided, prompt interactively.
# Sets: PROVIDER_API_KEY
provider_ensure_key() {
  if [ -n "${PROVIDER_API_KEY:-}" ]; then return 0; fi
  case "$PROVIDER" in
    bailian)   local p="Alibaba Cloud Bailian (DashScope)" ;;
    deepseek)  local p="DeepSeek (platform.deepseek.com)" ;;
    openrouter) local p="OpenRouter (openrouter.ai)" ;;
  esac
  printf '\n  Enter your %s API key.\n' "$p"
  printf '  (Get one at the provider site — see the providers guide on the bootstrap site.)\n'
  printf '  API key: '
  read -r PROVIDER_API_KEY
  if [ -z "$PROVIDER_API_KEY" ]; then
    err "no API key provided. Re-run with --api-key=..., or set it interactively."
  fi
  export PROVIDER_API_KEY
}

provider_print() {
  printf '  Provider:  %s\n' "$PROVIDER"
  printf '  Base URL:  %s\n' "$PROVIDER_BASE_URL"
  printf '  Model:     %s\n' "$PROVIDER_MODEL"
}

# Write ~/.claude/settings.json, merging our env block into any existing config.
# Uses a tiny Python helper (python3) for safe JSON merge.
provider_write_settings() {
  local claude_dir="${HOME}/.claude"
  local settings="$claude_dir/settings.json"
  mkdir -p "$claude_dir"

  # If python3 available, do a safe merge; else fall back to writing a minimal file.
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$settings" "$PROVIDER_BASE_URL" "$PROVIDER_API_KEY" "$PROVIDER_MODEL" <<'PY'
import json, os, sys
path, base, key, model = sys.argv[1:5]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
env = data.setdefault("env", {})
env["ANTHROPIC_BASE_URL"]   = base
env["ANTHROPIC_AUTH_TOKEN"] = key
env["ANTHROPIC_MODEL"]      = model
data["hasCompletedOnboarding"] = True
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  else
    cat > "$settings" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "$PROVIDER_BASE_URL",
    "ANTHROPIC_AUTH_TOKEN": "$PROVIDER_API_KEY",
    "ANTHROPIC_MODEL": "$PROVIDER_MODEL"
  },
  "hasCompletedOnboarding": true
}
EOF
  fi
  chmod 600 "$settings"
  note "wrote $settings"
}
