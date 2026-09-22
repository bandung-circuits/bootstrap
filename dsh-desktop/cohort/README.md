# cohort — per-training-cohort setup pages for DSH Desktop

For each training cohort, the organizer generates **one self-contained HTML page**
and sends the file to learners. The page contains a one-command setup whose
command has the cohort's shared Bailian API key baked in. The learner (who has
already installed DSH Desktop) runs it and gets a ready `~/ai-workspace` with
the key configured, the content-inspection header set, the default model pinned
to the cohort model (currently `deepseek-v4-flash-0731`), and permission set to
Full Access — no manual key entry.

This subtree is **separate from** the public `dsh-desktop/prep.*` flow. It
reuses the public prep verbatim (by running it) and only adds the provider/key
injection. The public site files (`prep.sh`, `prep.ps1`, `dsh-desktop.html`,
`index.html`, `templates/`) are not modified.

## Layout

```
generate.py            generator — bakes the key into a per-cohort HTML page
cohort-prep.sh         macOS learner command target (published to Pages, no secret)
cohort-prep.ps1        Windows learner command target (same)
inject_provider.py     single source of truth for the settings.yaml + .credentials.yaml
                       injection (provider, key, header, default model). Called by
                       both cohort-prep.* entries, never duplicated across languages.
templates/cohort-page.html   the per-cohort HTML page template
cohorts/               gitignored — generated pages contain the key, never commit
ci/smoke.sh            host-side smoke (inject unit tests + generator + real chat)
ci/fixtures/settings.sample.yaml   de-sanitized real settings.yaml for unit tests
```

## Generate a cohort page

From a clone of `bandung-circuits/bootstrap`:

```bash
python3 dsh-desktop/cohort/generate.py \
  --id 202609-nepal \
  --label "2026年9月 尼泊尔培训" \
  --key sk-xxxxxxxx
# optional: --model deepseek-v4-flash-0731  --base-url <bailian endpoint>
# key may also come from env BAILIAN_KEY or --key-file (keeps it out of shell history)
```

Output: `dsh-desktop/cohort/cohorts/202609-nepal.html` (gitignored — it contains
the key). Send that file to the cohort's learners out of band (email, chat,
class folder). **Do not publish it to GitHub Pages or commit it.**

The commands on the page point at the public cohort-prep scripts on Pages, so
fixing the script later upgrades all future cohorts without re-issuing old pages
(only the key differs per cohort).

## What the learner's command does

1. Runs the public `dsh-desktop/prep.sh` (or `.ps1`) verbatim — workspace,
   crawl4ai MCP, browser, Full Access permission. (Reuse; not duplicated.)
2. Calls `inject_provider.py`, which writes into the DSH Desktop harness dir:
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
→ a real minimal chat call to Bailian with the content-inspection header →
(optional) the same call with the cohort main model. The key is masked in all
logs; generated test artifacts use a dummy key and are deleted.

This smoke runs on the host (no VMware VM needed); the full prep.sh is already
CI-tested by the existing `ci/run-test.sh` VM flow.
