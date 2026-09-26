# dsh-desktop — one-command bootstrap for DSH Desktop learners

One command takes a fresh computer to a working DSH Desktop setup:

```bash
# macOS
curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh-desktop/setup.sh | bash
```

```powershell
# Windows
iex (curl.exe -sL https://bandung-circuits.github.io/bootstrap/dsh-desktop/setup.ps1 | Out-String)
```

1. **Installs DSH Desktop itself** if the app is missing — a PINNED release
   (see "Pinned DSH Desktop version" below), downloaded from the official
   GitHub releases and installed without any wizard. If the app is already
   installed, this step is skipped.
2. **Prepares a ready `~/ai-workspace`** by running `prep.*` (see below):
   - AGENTS.md (workspace rules), README.md, .gitignore, NEXT-STEPS.md seeds;
   - everything self-contained inside the workspace (the DSH Desktop app
     process does not put `~/.local/bin` on PATH and should never write to
     `~/.crawl4ai`): Python venv at `~/ai-workspace/.venv` with
     `crawl4ai-search-mcp==0.1.1`, Playwright Chromium at
     `~/ai-workspace/.browsers`, `uv` at `~/ai-workspace/.local/bin/uv`,
     crawl4ai data at `~/ai-workspace/.crawl4ai`;
   - enables the **crawl4ai** MCP server through the official
     `@deepseek-ai/dsh-mcp-client` by appending one patch insert to
     `<DSH Desktop app data>/harness/cordis.patch.yml` (absolute paths, no
     PATH dependence);
   - pins the default permission preset to Full Access.

The model backend key is NOT handled here: the learner signs up for a provider
and pastes their own key in the app (**Settings → Models**).

Platforms: macOS + Windows only (the app has no Linux build).

## Layering

```
install-dsh.sh / .ps1   shared front half: ensure DSH Desktop (pinned) is
                        installed. SINGLE SOURCE OF TRUTH for the pin.
setup.sh / setup.ps1    public learner entry: install-dsh + prep
prep.sh / prep.ps1      the workspace logic itself (also run directly by CI
                        and by the cohort chain; assumes nothing about the
                        app beyond the harness data dir)
templates/              the real static files prep copies + patches
```

Each layer only fetches/runs the next one; no logic is duplicated. All
entries are idempotent and safe to re-run: prep never overwrites existing
files, install-dsh skips when the app is present.

## prep.* design notes

- Everything configurable inside `~/ai-workspace` IS inside it (AGENTS.md,
  README, .gitignore, NEXT-STEPS). The one structurally-global write is the
  MCP patch in the app's harness data dir — the official mechanism for
  enabling an MCP server (each is external trusted code, machine-scoped by
  design).
- Idempotent and reversible: never overwrites existing files; the
  `mcp-crawl4ai` block can be removed by hand later.
- Pinned: `crawl4ai-search-mcp==0.1.1`, `uv/uvx` from the official installer;
  git lands as a portable MinGit inside the workspace on Windows, best-effort
  on macOS.

## Pinned DSH Desktop version

Both learner entries install a **pinned** DSH Desktop release when the app is
missing — currently `v0.9.2` (verified end to end with this flow), from the
official GitHub releases:

- macOS: DMG (`dsh-desktop-mac-arm64` / `-x64`), mounted and copied to
  `/Applications` (falls back to `~/Applications` without admin rights).
- Windows: NSIS setup with `/S`, per-user, no admin prompt, no windows. The
  learner is told it takes about 5 minutes and nothing is required from them.

The pin controls only what WE install; the app's own auto-updater still
offers newer versions afterwards and harness config survives upgrades (same
exposure as the manual-install flow). Bump the pin deliberately after
verifying a new version with the flow: change `DSH_VERSION` in
`install-dsh.sh` and `install-dsh.ps1` (the cohort smoke checks both agree
with the cohort page generator).

## Training cohorts

`cohort/` is a separate subtree for training-cohort setups where the organizer
pre-issues a shared Bailian API key per cohort. A generator bakes the key into a
per-cohort single-page HTML the organizer sends to learners; the learner's
one-command setup reuses the shared `install-dsh.*` front half above, then runs
the public prep verbatim, then injects the provider/key/content-inspection
header/default model. See [`cohort/README.md`](cohort/README.md). The public
files here are not modified by the cohort feature.

## Structure

```
install-dsh.sh / .ps1   shared front half: pinned DSH Desktop install
setup.sh / setup.ps1    public learner entry (install-dsh + prep)
prep.sh / prep.ps1      workspace logic (workspace, venv, crawl4ai MCP)
templates/              seeds for ~/ai-workspace + the crawl4ai patch insert
ci/                     VM + host verification for the prep path
cohort/                 training-cohort setup pages (separate subtree)
```
