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

# Write ~/ai-workspace/.claude/settings.local.json with the provider env block +
# sensible default permissions (mirrors the training workspace, but with only the
# free crawl4ai MCP — no key-bearing MCPs). Gitignored (contains the API key).
provider_write_settings() {
  local claude_dir="${WORKSPACE_DIR}/.claude"
  local settings="$claude_dir/settings.local.json"
  mkdir -p "$claude_dir"

  # Bailian (DashScope) benefits from disabling server-side data inspection.
  local extra_env=""
  if [ "$PROVIDER" = "bailian" ]; then
    extra_env='"ANTHROPIC_CUSTOM_HEADERS": "X-DashScope-DataInspection: {\"input\":\"disable\",\"output\":\"disable\"}",'
  fi

  if command -v python3 >/dev/null 2>&1; then
    PROVIDER_BASE_URL="$PROVIDER_BASE_URL" PROVIDER_API_KEY="$PROVIDER_API_KEY" \
    PROVIDER_MODEL="$PROVIDER_MODEL" EXTRA_ENV="$extra_env" \
    python3 - "$settings" <<'PY'
import json, os, sys
path = sys.argv[1]
base, key, model = os.environ["PROVIDER_BASE_URL"], os.environ["PROVIDER_API_KEY"], os.environ["PROVIDER_MODEL"]
try:
    with open(path) as f:
        data = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    data = {}
env = data.setdefault("env", {})
env["ANTHROPIC_BASE_URL"]   = base
env["ANTHROPIC_AUTH_TOKEN"] = key
env["ANTHROPIC_MODEL"]      = model
env["ANTHROPIC_DEFAULT_SONNET_MODEL"] = model
env["ANTHROPIC_DEFAULT_OPUS_MODEL"]   = model
env["API_TIMEOUT_MS"] = "3000000"
extra = os.environ.get("EXTRA_ENV", "").strip()
if extra:
    # extra is a fragment like '"k": "v",'; inject by parsing the wrapped object
    try:
        extra_obj = json.loads("{" + extra.rstrip(",") + "}")
        env.update(extra_obj)
    except Exception:
        pass
data.setdefault("permissions", {
    "allow": ["Bash(*)","Read","Write","Edit","Glob","Grep","Task",
              "mcp__crawl4ai__search","mcp__crawl4ai__read_url"],
    "deny": ["WebSearch","WebFetch"],
    "ask": []
})
data.setdefault("enabledMcpjsonServers", ["crawl4ai"])
data["hasCompletedOnboarding"] = True
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  else
    cat > "$settings" <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "$PROVIDER_BASE_URL",
    "ANTHROPIC_AUTH_TOKEN": "$PROVIDER_API_KEY",
    "ANTHROPIC_MODEL": "$PROVIDER_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "$PROVIDER_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "$PROVIDER_MODEL",
    "API_TIMEOUT_MS": "3000000"
  },
  "permissions": {
    "allow": ["Bash(*)","Read","Write","Edit","Glob","Grep","Task","mcp__crawl4ai__search","mcp__crawl4ai__read_url"],
    "deny": ["WebSearch","WebFetch"],
    "ask": []
  },
  "enabledMcpjsonServers": ["crawl4ai"],
  "hasCompletedOnboarding": true
}
EOF
  fi
  chmod 600 "$settings"
  note "wrote $settings"
}
