# dsh-desktop — one-command workspace prep for DSH Desktop learners

For people who already installed the **DSH Desktop** app (https://dshdesktop.com/en/),
this one-command script creates a ready `~/ai-workspace`:

1. Creates `~/ai-workspace` and seeds it: AGENTS.md (workspace rules),
   README.md, .gitignore, NEXT-STEPS.md.
2. Installs uv/uvx under the user's home (`~/.local/bin`) — the runner the
   crawl4ai MCP uses.
3. Enables the **crawl4ai** MCP server through the **official**
   `@deepseek-ai/dsh-mcp-client` (already bundled in DSH Desktop — no plugin
   install needed) by appending one patch insert to
   `<DSH Desktop app data>/harness/cordis.patch.yml`.

The model backend key is entered by the learner in the app itself
(**Settings → Models**); the prep never touches model credentials.

## Usage

macOS:
```bash
curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh-desktop/prep.sh | bash
```

Windows:
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://bandung-circuits.github.io/bootstrap/dsh-desktop/prep.ps1 | iex
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