# Next steps

Your AI workspace is ready at  ~/ai-workspace
(Windows:  C:\Users\<you>\ai-workspace )

## 1. Install DSH Desktop (if you haven't already)

Download from:  https://dshdesktop.com/en/

Supported: macOS (Apple Silicon and Intel) and Windows. Requires a user account
with normal permissions — no administrator needed for the workspace setup.

## 2. Add your model key

Open DSH Desktop, then go to **Settings → Models** and paste your DeepSeek API
key (get one at https://platform.deepseek.com/ or the provider of your choice).
The AI needs a model backend before it can answer.

## 3. Open this folder as the workspace

In the assistant, click **Choose workspace** and pick:

- macOS:  ~/ai-workspace
- Windows:  C:\Users\<you>\ai-workspace

## 4. Start using it

You can now ask the AI anything, e.g. "create a hello.py and run it".

The **crawl4ai** MCP (web fetch/search) is already enabled through the official
DSH MCP client — no key needed. The first search downloads a small helper
environment; this is automatic and needs internet.

---

*What the setup command did: created this folder with the workspace rules
(AGENTS.md), installed uv/uvx (the runner crawl4ai uses), and enabled the
crawl4ai MCP server in the DSH Desktop harness data. Nothing was moved or
deleted. To remove crawl4ai later, delete the `mcp-crawl4ai` block from
`<DSH Desktop data>/harness/cordis.patch.yml`.*