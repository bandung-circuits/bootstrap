# dsh-desktop — one-command workspace prep for DSH Desktop learners

For people who already installed the **DSH Desktop** app (https://dshdesktop.com/en/),
this one-command script creates a ready `~/ai-workspace`:

1. Creates `~/ai-workspace` and seeds it: AGENTS.md (workspace rules),
   README.md, .gitignore, NEXT-STEPS.md.
2. Installs everything **self-contained inside the workspace** (the DSH Desktop
   app process does not put `~/.local/bin` on PATH and should never write to
   `~/.crawl4ai`):
   - Python venv at `~/ai-workspace/.venv` with `crawl4ai-search-mcp==0.1.1`
     pre-installed;
   - Playwright Chromium pre-downloaded to `~/ai-workspace/.browsers`;
   - `uv` at `~/ai-workspace/.local/bin/uv` (helper, not needed at runtime);
   - crawl4ai data stays at `~/ai-workspace/.crawl4ai`.
3. Enables the **crawl4ai** MCP server through the **official**
   `@deepseek-ai/dsh-mcp-client` (bundled in DSH Desktop — no plugin install) by
   appending one patch insert to
   `<DSH Desktop app data>/harness/cordis.patch.yml`. The insert points the
   MCP client at the workspace venv's `crawl4ai-search` executable by absolute
   path, plus in-workspace env: `CRAWL4_AI_BASE_DIRECTORY` and
   `PLAYWRIGHT_BROWSERS_PATH`, so the server runs with no PATH/PATH dependency.

The model backend key is entered by the learner in the app itself
(**Settings → Models**); the prep never touches model credentials.

## Usage

macOS:
```bash
curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh-desktop/prep.sh | bash
```

Windows:
```powershell
iex (curl.exe -sL https://bandung-circuits.github.io/bootstrap/dsh-desktop/prep.ps1 | Out-String)
```

Prerequisite: DSH Desktop installed. Platforms: macOS + Windows only (the app
does not support Linux).

## Design notes

- Everything configurable inside `~/ai-workspace` IS inside it (AGENTS.md,
  README, .gitignore, NEXT-STEPS). The one structurally-global write is the MCP
  patch in the app's harness data dir — the official mechanism for enabling an
  MCP server (each is external trusted code, machine-scoped by design).
- Idempotent and reversible: never overwrites existing files; the `mcp-crawl4ai`
  block can be removed by hand later.
- Pinned: `crawl4ai-search-mcp==0.1.1`, `uv/uvx` from the official installer.

## Structure

```
prep.sh / prep.ps1           entry (mac / win)
templates/workspace/         seeds for ~/ai-workspace
templates/dsh-desktop/       the crawl4ai patch insert (single source of truth)
README.md                    this file
```