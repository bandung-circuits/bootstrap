#!/usr/bin/env bash
# provider.sh — resolve provider from region/override, build settings.json env block.
# Sourced by install.sh.

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

# Write ~/ai-workspace/.claude/settings.local.json with the provider env block +
# sensible default permissions (mirrors the training workspace, but with only the
# free crawl4ai MCP — no key-bearing MCPs). Gitignored (contains the API key).
provider_write_settings() {
  local claude_dir="${WORKSPACE_DIR}/.claude"
  local settings="$claude_dir/settings.local.json"
  mkdir -p "$claude_dir"

  # Bailian / DashScope (domestic & intl) benefits from disabling server-side data inspection.
  local extra_env=""
  if [ "$PROVIDER" = "bailian" ] || [ "$PROVIDER" = "bailian-intl" ]; then
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
    "deny": [],
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
    "deny": [],
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

# Write ~/ai-workspace/NEXT-STEPS.md — actionable onboarding (where to get a key,
# which file to edit, how to start). The installer doesn't prompt for a key, so
# this file walks the user through adding it after install.
provider_write_next_steps() {
  local p_site p_name
  case "$PROVIDER" in
    bailian)       p_site="https://bailian.console.aliyun.com/";            p_name="Alibaba Cloud Bailian (China)" ;;
    bailian-intl)  p_site="https://dashscope-intl.console.aliyun.com/";     p_name="Alibaba Cloud Model Studio (international)" ;;
    deepseek)      p_site="https://platform.deepseek.com/";                 p_name="DeepSeek" ;;
    openrouter)    p_site="https://openrouter.ai/";                        p_name="OpenRouter" ;;
  esac
  local steps="$WORKSPACE_DIR/NEXT-STEPS.md"
  cat > "$steps" <<EOF
# Next steps

Your AI workspace is set up at  ~/ai-workspace
One thing left: add your API key, then start using Claude Code.

## 1. Get an API key

Get a key for DeepSeek V4 Flash 0731 from $p_name:
  $p_site
(Full guide: https://bandung-circuits.github.io/bootstrap/providers-guide.html )

## 2. Paste your key into the config

Open this file:
  ~/ai-workspace/.claude/settings.local.json

Find the line:
  "ANTHROPIC_AUTH_TOKEN": "PASTE-YOUR-API-KEY-HERE"

Replace  PASTE-YOUR-API-KEY-HERE  with your real key. Save the file.
$( [ "${PROVIDER_KEY_IS_PLACEHOLDER:-0}" = "1" ] || echo "
(Note: an API key was already provided to the installer — you can skip this step
if that key is the one you intend to use.)" )

## 3. Start using Claude Code

Open VS Code in this workspace:
  code ~/ai-workspace

The Claude Code chat panel opens automatically (as an editor tab). If it
doesn't, click the Spark icon (top-right of the editor). Ask it anything,
e.g.  "create a hello.py and run it".

The crawl4ai MCP (web fetch/search) is already configured — no key needed.
EOF
  note "wrote $steps"
}
