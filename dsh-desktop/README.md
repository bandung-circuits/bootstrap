# dsh-desktop — one-command bootstrap for DeepSeek Harness desktop learners

One command takes a fresh computer to a working **DeepSeek Harness** desktop
setup:

```bash
# macOS (Apple silicon)
curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh-desktop/setup.sh | bash
```

```powershell
# Windows
iex (curl.exe -sL https://bandung-circuits.github.io/bootstrap/dsh-desktop/setup.ps1 | Out-String)
```

1. **Installs the official DeepSeek Harness desktop app** if it's missing —
   downloaded from DeepSeek's own CDN (`download.deepseek.com`, the same
   `dsh-latest-*` artifacts deepseek.com/download links to) and installed
   without any wizard. If the app is already installed, this step is skipped.
2. **Prepares a ready `~/ai-workspace`** by running `prep.*` (see below):
   - AGENTS.md (workspace rules), README.md, .gitignore, NEXT-STEPS.md seeds;
   - everything self-contained inside the workspace: Python venv at
     `~/ai-workspace/.venv` with `crawl4ai-search-mcp==0.1.1`, Playwright
     Chromium at `~/ai-workspace/.browsers`, `uv` at
     `~/ai-workspace/.local/bin/uv`, crawl4ai data at
     `~/ai-workspace/.crawl4ai`;
   - enables the **crawl4ai** MCP server through the official
     `@deepseek-ai/dsh-mcp-client` by appending one insert to the desktop
     profile's patch layer `<DSH_HOME>/profiles/desktop/cordis.patch.yml`
     (default `~/.dsh/profiles/desktop`, absolute paths, no PATH dependence);
   - pins the default permission preset to Full Access;
   - installs two default plugins into the `desktop` profile
     (`dshmarket`, `dsh-better-reasoning-effort`) using the app's own bundled
     dsh CLI + pnpm.

The model backend key is NOT handled here: the learner signs up for a provider
and pastes their own key in the app (**Settings → Models**).

Platforms: Apple-silicon macOS + Windows x64 only (the official desktop has no
Intel Mac or Linux build — those users use `npx @deepseek-ai/dsh web`).

## About the app

This flow installs the **official** DeepSeek Harness desktop client
(`deepseek-ai/deepseek-harness`, Electron shell around the dsh runtime) — not
any third-party wrapper. It uses the shared dsh data root `~/.dsh`, in the
`desktop` profile; the config below lives in `~/.dsh/profiles/desktop`.

## Layering

```
install-dsh.sh / .ps1   shared front half: ensure DeepSeek Harness (pinned) is
                        installed. SINGLE SOURCE OF TRUTH for the pin.
setup.sh / setup.ps1    public learner entry: install-dsh + prep
prep.sh / prep.ps1      the workspace logic itself (also run directly by CI
                        and by the cohort chain; assumes nothing about the
                        app beyond the ~/.dsh data root)
templates/              the real static files prep copies + patches
```

Each layer only fetches/runs the next one; no logic is duplicated. All
entries are idempotent and safe to re-run: prep never overwrites existing
files, install-dsh skips when the app is present.

## prep.* design notes

- Everything configurable inside `~/ai-workspace` IS inside it (AGENTS.md,
  README, .gitignore, NEXT-STEPS). The two structurally-global writes are in
  the desktop profile at `~/.dsh/profiles/desktop`: the MCP insert in
  `cordis.patch.yml` (the official mechanism for enabling an MCP server) and a
  legacy `settings.yaml` the app imports on first load
  (`permission.defaultPreset`). Each is external trusted config, machine-scoped
  by design.
- Idempotent and reversible: never overwrites existing files; the
  `mcp-crawl4ai` block can be removed by hand later.
- Crawl4ai is a heavy stack and its Playwright Chromium is the biggest part.
  The official app bundles its own Python only for the three Office skills; it
  does NOT bundle crawl4ai, and we deliberately keep crawl4ai in our own
  `~/ai-workspace/.venv` rather than putting it into the app-managed runtime
  (`~/.dsh/dsh-runtimes/...`, re-materialized from DeepSeek's lock manifest and
  thus not a stable anchor). See the crawl4ai-patch comment + AGENTS for the
  reasoning.
- Pinned: `crawl4ai-search-mcp==0.1.1`, `uv/uvx` from the official installer;
  git lands as a portable MinGit inside the workspace on Windows, best-effort
  on macOS.

## Pinned DeepSeek Harness version

The official download is an always-current pointer (`dsh-latest-*`, the same
ones deepseek.com/download links). There is no versioned public URL, so we pin
by recording the version observed from the pointer plus the artifact's SHA-512,
and re-verify deliberately when the pointer moves:

- Current pin: `0.2.0-rc.2`
- macOS dmg sha512: `6b88f10d…` (recorded in `install-dsh.sh`; if a future
  download no longer hashes to it, the pin is bumped deliberately after
  re-verifying end to end).

The pin controls only what WE install; the app's own in-app updater still
offers newer versions afterwards and it uses the same `~/.dsh` data root, so
harness config survives upgrades (same exposure as the manual-install flow).
Bump `DSH_VERSION` + `SHASUM_512` in `install-dsh.sh` / `install-dsh.ps1` and
`DSH_VERSION` in `cohort/generate.py` together after re-verifying (the cohort
smoke checks all three agree).

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
install-dsh.sh / .ps1   shared front half: pinned DeepSeek Harness install
setup.sh / setup.ps1    public learner entry (install-dsh + prep)
prep.sh / prep.ps1      workspace logic (workspace, venv, crawl4ai MCP)
templates/              seeds for ~/ai-workspace + the crawl4ai patch insert
ci/                     VM + host verification for the prep path
cohort/                 training-cohort setup pages (separate subtree)
```