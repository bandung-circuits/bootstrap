# My AI workspace

This folder is your default workspace for DeepSeek Harness (`dsh`). Keep your projects here.

## Quick start

1. Start the assistant: double-click **start-dsh.sh** (Linux/macOS) or **start-dsh.cmd** (Windows).
2. Your browser opens DeepSeek Harness at `http://127.0.0.1:3080`.
3. Tell the AI what you want, e.g.:
   - "create a hello.py and run it"
   - "find recent news about <topic> and save it to news.md"
   - "explain what's in this folder"

The backend is DeepSeek V4 Flash 0731. The crawl4ai MCP (web fetch/search) is ready, and the harness also ships built-in web search and fetch.

## Notes

- Your API key lives in `.dsh/secrets.env` (or you can paste it in the UI under Settings → Models).
- `.dsh/` is the harness home — don't edit it by hand unless you know what you're doing.