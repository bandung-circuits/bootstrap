#!/usr/bin/env python3
# inject_provider.py — the single source of truth for wiring a training-cohort
# provider (Bailian / Alibaba Cloud Model Studio) into a DSH Desktop harness.
#
# Invoked by cohort-prep.sh (mac) and cohort-prep.ps1 (win) AFTER the public
# dsh-desktop/prep.* has already run (workspace, crawl4ai MCP, permission
# default). This script only does the two things prep.* deliberately leaves to
# the learner — configure the model provider + API key — plus the content-
# inspection header that the bailian-content-inspection page documents, and pin
# the session's default model.
#
# What it writes (all inside the DSH Desktop harness data dir):
#   settings.yaml   — the `training` provider block + `agent-default-model`
#   .credentials.yaml — `refs.TRAINING_API_KEY` (the key the cohort shares)
#
# Design: line/block surgery on the raw files, NOT a full pyyaml round-trip, so
# every byte outside the two touched blocks stays identical to what the learner
# (or the app) had. This mirrors dsh-desktop/prep.sh's awk/python precedent
# (it edits `permission.defaultPreset` in place; it never round-trips the file).
# pyyaml is only used to *read* structure when deciding insert-vs-replace.
#
# Idempotent: re-running with the same cohort params rewrites the same canonical
# block → net zero change. Other providers the learner added by hand are never
# touched.

import argparse
import os
import re
import shutil
import sys

API_KEY_ENV = "TRAINING_API_KEY"
HEADER_VALUE = '{"input":"disable","output":"disable"}'
DEFAULT_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
DEFAULT_MODEL = "deepseek-v4-flash-0731"
DEFAULT_PROVIDER_ID = "training"
DEFAULT_LABEL = "Training"

HEADER_LINE = '        X-DashScope-DataInspection: \'{"input":"disable","output":"disable"}\''


def note(msg):
    print(f"==> {msg}")


def err(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def backup(path):
    """One-shot pristine backup. Keeps the FIRST pre-cohort state for undo."""
    bak = path + ".dsh-bak"
    if os.path.exists(path) and not os.path.exists(bak):
        shutil.copy2(path, bak)
        note(f"backed up {path} -> {bak}")


# ---------- provider block ----------

def provider_block(pid, base_url, model, label):
    """The canonical 4-space-indented provider block (sibling of other providers
    under `llm-pi-ai: -> providers:`). 6-space fields, matching the file's
    existing style."""
    return [
        f"    {pid}:",
        "      api: openai-responses",
        f"      apiKeyEnv: {API_KEY_ENV}",
        f"      baseURL: {base_url}",
        f"      displayName: {label}",
        "      headers:",
        f"        X-DashScope-DataInspection: '{HEADER_VALUE}'",
        "      models:",
        f"      - id: {model}",
    ]


def patch_provider(lines, pid, base_url, model, label):
    """Replace the `    <pid>:` block if present, else insert under `  providers:`.
    Returns new lines list."""
    pat = re.compile(rf"^    {re.escape(pid)}:\s*$")
    start = next((i for i, ln in enumerate(lines) if pat.match(ln)), -1)
    block = provider_block(pid, base_url, model, label)

    if start >= 0:
        # block end = next sibling provider (4-space, non-blank) or top-level key.
        end = len(lines)
        for i in range(start + 1, len(lines)):
            if re.match(r"^(\S|    \S)", lines[i]):
                end = i
                break
        # also swallow trailing blank lines that belonged to the old block.
        while end - 1 > start and lines[end - 1].strip() == "":
            end -= 1
        return lines[:start] + block + lines[end:]

    # insert: prefer right after `  providers:`; else build the wrapper.
    for i, ln in enumerate(lines):
        if re.match(r"^  providers:\s*$", ln):
            return lines[: i + 1] + block + lines[i + 1:]
    # no `  providers:` line; look for `llm-pi-ai:` and add providers: + block.
    for i, ln in enumerate(lines):
        if re.match(r"^llm-pi-ai:\s*$", ln):
            return lines[: i + 1] + ["  providers:"] + block + lines[i + 1:]
    # no llm-pi-ai at all — append the whole subtree.
    # keep one blank line separator if the file is non-empty and lacks a trailing newline.
    head = lines[:]
    if head and head[-1].strip() != "":
        head.append("")
    return head + ["llm-pi-ai:", "  providers:"] + block


# ---------- agent-default-model block ----------

def adm_block(pid, model):
    return [
        "agent-default-model:",
        f"  provider: {pid}",
        f"  model: {model}",
    ]


def patch_agent_default_model(lines, pid, model):
    """Replace or append the top-level `agent-default-model:` block."""
    start = next(
        (i for i, ln in enumerate(lines) if re.match(r"^agent-default-model:\s*$", ln)),
        -1,
    )
    block = adm_block(pid, model)
    if start >= 0:
        end = len(lines)
        for i in range(start + 1, len(lines)):
            if re.match(r"^\S", lines[i]):
                end = i
                break
        return lines[:start] + block + lines[end:]
    # append at EOF
    head = lines[:]
    if head and head[-1].strip() != "":
        head.append("")
    return head + [""] + block


# ---------- credentials ----------

def patch_credentials(lines, key):
    """Line-surgery on .credentials.yaml: set `refs.TRAINING_API_KEY`.
    Quoted scalar — keys may contain dots/dashes; quoting is always safe."""
    val = f"  {API_KEY_ENV}: '{key}'"
    # existing ref line?
    for i, ln in enumerate(lines):
        if re.match(rf"^  {API_KEY_ENV}:\s", ln):
            lines[i] = val
            return lines
    # existing refs: block?
    for i, ln in enumerate(lines):
        if re.match(r"^refs:\s*$", ln):
            return lines[: i + 1] + [val] + lines[i + 1:]
    # no refs at all — append a refs block.
    head = lines[:]
    if head and head[-1].strip() != "":
        head.append("")
    return head + ["refs:", val]


# ---------- main ----------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--harness-home", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--label", default=DEFAULT_LABEL)
    ap.add_argument("--provider-id", default=DEFAULT_PROVIDER_ID)
    args = ap.parse_args()

    if not args.key:
        err("empty API key")
    harness = args.harness_home
    if not os.path.isdir(harness):
        os.makedirs(harness, exist_ok=True)

    settings = os.path.join(harness, "settings.yaml")
    creds = os.path.join(harness, ".credentials.yaml")

    # --- settings.yaml ---
    backup(settings)
    if os.path.exists(settings):
        raw = open(settings, encoding="utf-8").read()
        had_trailing_nl = raw.endswith("\n")
        lines = raw.splitlines()
    else:
        lines, had_trailing_nl = [], False
    lines = patch_provider(lines, args.provider_id, args.base_url, args.model, args.label)
    lines = patch_agent_default_model(lines, args.provider_id, args.model)
    out = "\n".join(lines)
    if had_trailing_nl or os.path.exists(settings):
        out += "\n"
    open(settings, "w", encoding="utf-8").write(out)
    os.chmod(settings, 0o644)
    note(f"wrote provider `{args.provider_id}` + agent-default-model in {settings}")

    # --- .credentials.yaml ---
    backup(creds)
    if os.path.exists(creds):
        raw = open(creds, encoding="utf-8").read()
        had_trailing_nl = raw.endswith("\n")
        clines = raw.splitlines()
    else:
        clines, had_trailing_nl = [], False
    clines = patch_credentials(clines, args.key)
    cout = "\n".join(clines)
    if had_trailing_nl or not os.path.exists(creds):
        cout += "\n"
    # the app keeps credentials 0600; preserve/create that.
    open(creds, "w", encoding="utf-8").write(cout)
    os.chmod(creds, 0o600)
    note(f"wrote {API_KEY_ENV} into {creds}")

    print(
        f"\nDone. Provider `{args.provider_id}` -> model `{args.model}` "
        f"at {args.base_url}, content-inspection header set, key stored.\n"
        f"Open DSH Desktop, choose workspace ~/ai-workspace, and start."
    )


if __name__ == "__main__":
    main()
