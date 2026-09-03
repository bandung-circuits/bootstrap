# Next steps

Your AI workspace is ready at  ~/ai-workspace
(Windows:  C:\Users\<you>\ai-workspace )

## 1. Install DSH Desktop (if you haven't already)

Download from:  https://dshdesktop.com/en/

Supported: macOS (Apple Silicon and Intel) and Windows. Requires a user account
with normal permissions — no administrator needed for the workspace setup.

## 2. Add the model key

The app needs a model service. If you haven't set it up yet: sign up with OpenRouter
(recommended, https://openrouter.ai/) or Alibaba Cloud Model Studio (international,
https://www.alibabacloud.com/), get an API key, then paste it into the app at
**Settings → Models**. The AI cannot answer until this is done.

## 3. Open this folder as the workspace

In the assistant, click **Choose workspace** and pick:

- macOS:  ~/ai-workspace
- Windows:  C:\Users\<you>\ai-workspace

## 4. Start using it

You can now ask the AI anything, e.g. "find recent news about <topic> and save a
short summary to news.md", or "draft a one-page briefing note about <event> in
plain language".

The **crawl4ai** MCP (web fetch/search) is already enabled through the official
DSH MCP client — no key needed. The first search downloads a small helper
environment; this is automatic and needs internet.

---

*What the setup command did: created this folder with the workspace rules
(AGENTS.md), installed uv/uvx (the runner crawl4ai uses), and enabled the
crawl4ai MCP server in the DSH Desktop harness data. Nothing was moved or
deleted. To remove crawl4ai later, delete the `mcp-crawl4ai` block from
`<DSH Desktop data>/harness/cordis.patch.yml`.*