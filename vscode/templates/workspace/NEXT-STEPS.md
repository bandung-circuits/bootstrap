# Next steps

Your AI workspace is set up at  ~/ai-workspace
One thing left: add your API key, then start using Claude Code.

## 1. Get an API key

Get a key for DeepSeek V4 Flash 0731 from {{PROVIDER_NAME}}:
  {{PROVIDER_SITE}}
(Full guide: https://bandung-circuits.github.io/bootstrap/providers-guide.html )

## 2. Paste your key into the config

Open this file:
  ~/ai-workspace/.claude/settings.local.json

Find the line:
  "ANTHROPIC_AUTH_TOKEN": "PASTE-YOUR-API-KEY-HERE"

Replace  PASTE-YOUR-API-KEY-HERE  with your real key. Save the file.{{KEY_NOTICE}}

## 3. Start using Claude Code

Open VS Code in this workspace:
  code ~/ai-workspace

The Claude Code panel is docked in the sidebar (right) and opens with VS Code.
It never opens in the center tab by itself. Ask it anything,
e.g.  "create a hello.py and run it".

The crawl4ai MCP (web fetch/search) is already configured — no key needed.