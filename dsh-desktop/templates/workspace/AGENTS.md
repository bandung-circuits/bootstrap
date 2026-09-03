# AGENTS.md — Workspace Conventions

This file defines the working conventions for AI agents (and humans) operating in this workspace. Agents opened in this folder are expected to follow it.

## 1. Default working language: English

- The default working language of this workspace is **simple, plain English**.
- All agent outputs, documentation, and deliverables default to English, unless a task explicitly requests another language.
- This workspace is being prepared as a training template for **non-technical AI beginners**. Write for that audience: short sentences, common vocabulary, concrete examples, and no jargon without a one-line explanation.

## 2. Web tools: prefer crawl4ai when its tools are present

Prefer the **crawl4ai** MCP (free, no API key) when its tools are listed in this
session's toolset:

- `mcp__crawl4ai__read_url` to fetch a page (or PDF) in full.
- `mcp__crawl4ai__search` to search the web.

**Check the toolset once at the start.** If the `mcp__crawl4ai__*` tools are not
listed, they will not appear mid-session — do not keep retrying them. Fall back
in this order:

1. **Diagnose** briefly: MCP tools register only when the server process starts,
   and the server is launched exactly by `command` in
   `<DSH Desktop data>/harness/cordis.patch.yml`. If reading that file is quick,
   check that the pinned `command` path exists on disk. A wrong path means the
   setup command needs to be re-run (it self-heals the row) and the session
   reopened.
2. **Run crawl4ai directly** from the workspace venv — same engine, no MCP
   needed. Use the venv python (see section 3) to run scripts, or
   `~/ai-workspace/.venv/bin/crawl4ai-search` (macOS) /
   `.venv\Scripts\crawl4ai-search.exe` (Windows) for the CLI. Its first real
   use creates `.crawl4ai` folders inside the workspace.
3. **Built-in harness tools**: `web_fetch` needs no key. `web_search` needs the
   model key configured (Settings → Models in the app) — if it fails with a
   missing-key error, note that to the user rather than retrying forever.

If a crawl4ai call times out or returns "not found" on the first attempt, retry
once (the browser may still be finishing its pre-installed set-up); then move
down the ladder. The browser it uses was pre-downloaded into
`~/ai-workspace/.browsers`.

## 3. Python and dependencies live in this workspace

Everything was installed self-contained inside this folder — do not look for
Python, tools, or packages outside it:

- **Python** (with the crawl4ai package pre-installed):
  - macOS: `~/ai-workspace/.venv/bin/python`
  - Windows: `C:\Users\<you>\ai-workspace\.venv\Scripts\python.exe`
- **uv** (package/runtime manager, if you need to install more):
  - `~/ai-workspace/.local/bin/uv` (macOS) / `.local\bin\uv.exe` (Windows)

To run a Python script, use the workspace venv's interpreter, e.g.
`~/ai-workspace/.venv/bin/python analyze.py` — not a system `python`. The venv
automatically directs crawl4ai's data and browser into this workspace. If you
need to install another package, use the workspace uv:
`uv pip install -p ~/ai-workspace/.venv <package>`.

## 4. Grounded search principles

These rules apply whenever an agent searches the web or consults external sources.

**Search summaries are not trustworthy — always fetch the full text of the original page before citing anything.**

Reference: [BHV-05 Grounded Web Research](https://github.com/eXtremeProgramming-cn/pomasa/blob/main/skills/pomasa/pattern-catalog/BHV-05-grounded-web-research.md)

1. **Locate sources first.** Use search only to find potentially relevant sources; never treat summaries, snippets, or cached snapshots as evidence.
2. **Verify against the original.** All key information — conclusions, numbers, names, and attributions — must be checked against the full text of the original page or the original source file.
3. **Cite to origin.** Every claim written into an output must trace back to an original source text. Any statement that cannot be supported by an original source must not be included in the output.

## 5. The harness data lives outside this folder

This workspace is used with the **DSH Desktop** application. The harness's own data (profiles, plugins, sessions) lives in the application's data directory, not in this folder — the app-data folder is most often the package name `dsh-desktop` (sometimes `DSH Desktop`, depending on the build):

- macOS: `~/Library/Application Support/dsh-desktop/harness` (or `.../DSH Desktop/harness`)
- Windows: `%APPDATA%\dsh-desktop\harness` (or `%APPDATA%\DSH Desktop\harness`)

Treat that directory as machinery — editing it is a config change and requires an explicit user request. Two files there are worth READING for diagnosis:

- `settings.yaml` — holds the default permission preset (`permission.defaultPreset`).
- `cordis.patch.yml` — the MCP server registrations (including crawl4ai) and the exact `command` paths they launch.

Keep your own work in this workspace root or a project subfolder.

## 6. Scope note

Additional conventions (safety defaults, packaging) will be added to this file in later iterations.

## 7. Quick environment self-check

When web or MCP behavior looks wrong, check in this order:

1. Are `mcp__crawl4ai__*` tools in the session toolset? (They register only at session start.)
2. Is the server registered and its `command` path real? (Read `cordis.patch.yml`; check the file exists.)
3. Is crawl4ai importable? (`~/ai-workspace/.venv/bin/python -c "import crawl4ai_mcp_server"`)
4. Is the browser pre-downloaded? (`~/ai-workspace/.browsers`)
5. Is `web_search` configured? (model key in Settings → Models of the app)

A broken `command` path means re-running the setup command — it rewrites the row correctly — then reopening the session.