# cohort — per-training-cohort setup pages for DSH Desktop

For each training cohort, the organizer generates **one self-contained HTML page**
and sends the file to learners. The page contains a one-command setup whose
command has the cohort's shared Bailian API key baked in. The learner runs it
and gets everything on a fresh computer: DSH Desktop itself (pinned version,
installed silently if missing) plus a ready `~/ai-workspace` with the key
configured, the content-inspection header set, the default model pinned to the
cohort model (currently `deepseek-v4-flash-0731`), and permission set to Full
Access — no manual key entry, no separate app download.

This subtree is **separate from** the public `dsh-desktop/prep.*` flow. It
reuses the public prep verbatim (by running it) and only adds (a) the pinned
DSH Desktop install when the app is missing and (b) the provider/key injection.
The public site files (`prep.sh`, `prep.ps1`, `dsh-desktop.html`, `index.html`,
`templates/`) are not modified.

## Layout

```
generate.py            generator — bakes the key into a per-cohort HTML page
cohort-setup.sh        macOS learner command target: DSH Desktop (pinned) if
                       missing, then cohort-prep.sh (published to Pages, no secret)
cohort-setup.ps1       Windows learner command target (same)
cohort-prep.sh         macOS: public prep + provider/key injection (called by
                       cohort-setup.sh; also usable directly when the app is
                       already installed)
cohort-prep.ps1        Windows: same
inject_provider.py     single source of truth for the settings.yaml + .credentials.yaml
                       injection (provider, key, header, default model). Called by
                       cohort-prep.*, never duplicated across languages.
templates/cohort-page.html   the per-cohort HTML page template
cohorts/               gitignored — generated pages contain the key, never commit
ci/smoke.sh            host-side smoke (inject unit tests + generator + setup glue + real chat)
ci/fixtures/settings.sample.yaml   de-sanitized real settings.yaml for unit tests
```

## Pinned DSH Desktop version

On a fresh machine the learner command downloads and silently installs a
**pinned** DSH Desktop release — currently `v0.9.2` (verified end to end with
this flow), from the official GitHub releases. The install logic and the pin
live in the shared front half [`../install-dsh.sh` / `.ps1`](../README.md)
(also used by the public `setup.*` entry); see that README for platform
details. `generate.py` carries the same version for the cohort page text.

The pin controls only what WE install; the app's own auto-updater still offers
newer versions afterwards and harness config survives upgrades (same exposure
as the manual-install flow). Bump the pin deliberately after verifying a new
version with the cohort flow: change `DSH_VERSION` in `../install-dsh.sh`,
`../install-dsh.ps1`, and `generate.py` (the smoke checks all three agree).


## Generate a cohort page

From a clone of `bandung-circuits/bootstrap`:

```bash
python3 dsh-desktop/cohort/generate.py \
  --id 202609-nepal \
  --label "2026年9月 尼泊尔培训" \
  --key sk-xxxxxxxx
# optional: --model deepseek-v4-flash-0731  --base-url <bailian endpoint>
# key may also come from env BAILIAN_KEY or --key-file (keeps it out of shell history)
# --lang ne  adds Nepali learner-step lines under the English (omit = English only)
```

Output: `dsh-desktop/cohort/cohorts/202609-nepal.html` (gitignored — it contains
the key). Send that file to the cohort's learners out of band (email, chat,
class folder). **Do not publish it to GitHub Pages or commit it.**

The commands on the page point at the public cohort-setup scripts on Pages, so
fixing the script later upgrades all future cohorts without re-issuing old pages
(only the key differs per cohort). Note this also means a pin bump (or any
setup-script change) reaches future learners on old pages automatically.

Page design notes: the page is aimed at learners with no IT background. It shows
three numbered steps (open the terminal, copy via a big green button, paste +
Enter), styles the command as a mock terminal window so learners recognise the
real one, auto-detects the OS and shows only one command, and shows a sample of
the script's exact final output ("Setup complete!" banner printed by the
cohort-setup scripts — keep the two in sync). `--lang` adds second-language
learner lines (currently `ne` = Nepali; machine-drafted, have a native speaker
review before the next cohort). The DSH Desktop app icon (`assets/`) is
embedded as a data URI so the page stays a single self-contained file.

## What the learner's command does

1. Installs DSH Desktop if it is missing (pinned version, silent — see above);
   skips this when the app is already installed.
2. Runs the public `dsh-desktop/prep.sh` (or `.ps1`) verbatim — workspace,
   crawl4ai MCP, browser, Full Access permission. (Reuse; not duplicated.)
3. Calls `inject_provider.py`, which writes into the DSH Desktop harness dir:
   - `settings.yaml` — the `training` provider (baseURL, `apiKeyEnv`,
     `X-DashScope-DataInspection: {"input":"disable","output":"disable"}`,
     models), and `agent-default-model` pinned to the cohort model.
   - `.credentials.yaml` — `refs.TRAINING_API_KEY` (the key).
   Both via line/block surgery with a one-shot pristine `.dsh-bak` backup;
   other providers the learner added are never touched. Idempotent on re-run.

The content-inspection header is the one documented at
<https://extremeprogramming-cn.github.io/bailian-content-inspection/> — it
suppresses false `DataInspectionFailed` blocks on legitimate research material at
the platform layer (the model's own compliance is unaffected).

## Smoke test (organizer side)

Put a real Bailian key in the gitignored root `.env` (copy from `.env.example`):

```
COHORT_CI_KEY=sk-…real-key…
COHORT_CI_MODEL=qwen-turbo        # cheap model for the smoke call
# COHORT_CI_VERIFY_MAIN_MODEL=1   # also call deepseek-v4-flash-0731
```

Then:

```bash
bash dsh-desktop/cohort/ci/smoke.sh
```

It runs: inject unit tests (replace + insert paths, idempotency) → generator
test (dummy key) → `cohort-prep.sh` end-to-end glue (prep stubbed, temp harness)
→ `cohort-setup.sh` glue (pin consistency, key guard, app-detect + delegate)
→ a real minimal chat call to Bailian with the content-inspection header →
(optional) the same call with the cohort main model. The key is masked in all
logs; generated test artifacts use a dummy key and are deleted.

This smoke runs on the host (no VMware VM needed); the full prep.sh is already
CI-tested by the existing `ci/run-test.sh` VM flow.
