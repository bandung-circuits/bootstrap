#!/usr/bin/env python3
# generate.py — produce a per-cohort single-page HTML setup guide for DSH Desktop
# learners. The cohort's Bailian API key is baked into the commands on the page.
#
# Run from a clone:
#   python3 dsh-desktop/cohort/generate.py \
#     --id 202609-nepal --label "2026年9月 尼泊尔培训" --key sk-xxxxxxxx
#
# Output: dsh-desktop/cohort/cohorts/<id>.html  (contains a secret — never commit,
# never publish; hand the file to learners out of band). The cohorts/ dir is
# gitignored. The key may also be read from env BAILIAN_KEY or --key-file, to keep
# it out of shell history.
#
# The commands on the page point learners at the public cohort-prep scripts on
# GitHub Pages. Only the key (and any non-default param) is embedded in the
# command; the logic scripts stay public and upgradeable without re-issuing old
# pages.

import argparse
import html
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO_BASE = "https://bandung-circuits.github.io/bootstrap"
COHORT_SETUP_MAC = f"{REPO_BASE}/dsh-desktop/cohort/cohort-setup.sh"
COHORT_SETUP_WIN = f"{REPO_BASE}/dsh-desktop/cohort/cohort-setup.ps1"

# Pinned DSH Desktop release the setup command installs when the app is
# missing. Must match the DSH_VERSION default in cohort-setup.sh/.ps1 (the
# cohort smoke checks the three agree). Bump deliberately after verifying the
# new version with the cohort flow.
DSH_VERSION = "v0.9.2"

DEFAULT_MODEL = "deepseek-v4-flash-0731"
DEFAULT_BASE_URL = "https://dashscope.aliyuncs.com/compatible-mode/v1"
DEFAULT_LABEL = "Training"
DEFAULT_PROVIDER = "training"


def build_mac_command(key, model, base_url, label, provider):
    """macOS: curl | VAR=x bash. Only emit env vars that differ from defaults."""
    env = [("TRAINING_API_KEY", key)]
    if model != DEFAULT_MODEL:
        env.append(("MODEL", model))
    if base_url != DEFAULT_BASE_URL:
        env.append(("BASE_URL", base_url))
    if label != DEFAULT_LABEL:
        env.append(("LABEL", label))
    if provider != DEFAULT_PROVIDER:
        env.append(("PROVIDER_ID", provider))
    prefix = " ".join(f"{k}='{v}'" for k, v in env)
    return f"curl -fsSL {COHORT_SETUP_MAC} | {prefix} bash"


def build_win_command(key, model, base_url, label, provider):
    """Windows PowerShell: set env vars, then iex the fetched script."""
    env = [f"$env:TRAINING_API_KEY='{key}'"]
    if model != DEFAULT_MODEL:
        env.append(f"$env:MODEL='{model}'")
    if base_url != DEFAULT_BASE_URL:
        env.append(f"$env:BASE_URL='{base_url}'")
    if label != DEFAULT_LABEL:
        env.append(f"$env:LABEL='{label}'")
    if provider != DEFAULT_PROVIDER:
        env.append(f"$env:PROVIDER_ID='{provider}'")
    prefix = "; ".join(env)
    return f"{prefix}; iex (curl.exe -sL {COHORT_SETUP_WIN} | Out-String)"


def read_key(args):
    if args.key:
        return args.key
    if args.key_file:
        return open(args.key_file, encoding="utf-8").read().strip()
    env_key = os.environ.get("BAILIAN_KEY")
    if env_key:
        return env_key
    sys.exit("ERROR: no key. Pass --key, --key-file, or set BAILIAN_KEY.")


def main():
    ap = argparse.ArgumentParser(description="Generate a per-cohort setup HTML page.")
    ap.add_argument("--id", required=True, help="cohort id (filename + shown as Cohort: …)")
    ap.add_argument("--label", default=DEFAULT_LABEL, help="provider displayName + page title")
    ap.add_argument("--key", help="the Bailian API key (baked into the commands)")
    ap.add_argument("--key-file", help="read the key from this file instead of --key")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--base-url", default=DEFAULT_BASE_URL)
    ap.add_argument("--provider", default=DEFAULT_PROVIDER)
    args = ap.parse_args()

    key = read_key(args)
    if not key:
        sys.exit("ERROR: empty key.")
    for name, val in (("--label", args.label), ("--id", args.id)):
        if "'" in val:
            sys.exit(f"ERROR: {name} must not contain a single quote (it goes into a shell-quoted command).")

    mac_cmd = build_mac_command(key, args.model, args.base_url, args.label, args.provider)
    win_cmd = build_win_command(key, args.model, args.base_url, args.label, args.provider)

    tpl = open(os.path.join(HERE, "templates", "cohort-page.html"), encoding="utf-8").read()
    # HTML-escape the command strings (keys are safe chars, but be correct).
    out = (
        tpl.replace("{{LABEL}}", html.escape(args.label))
        .replace("{{COHORT_ID}}", html.escape(args.id))
        .replace("{{MODEL}}", html.escape(args.model))
        .replace("{{DSH_VERSION}}", html.escape(DSH_VERSION))
        .replace("{{MAC_COMMAND}}", html.escape(mac_cmd))
        .replace("{{WIN_COMMAND}}", html.escape(win_cmd))
    )

    out_dir = os.path.join(HERE, "cohorts")
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{args.id}.html")
    open(out_path, "w", encoding="utf-8").write(out)
    print(f"wrote {out_path}")
    print(f"  cohort: {args.id}  model: {args.model}")
    # keep the key out of our own stdout.
    masked = key[:4] + "…" + key[-4:] if len(key) > 8 else "…"
    print(f"  key (masked): {masked}")
    print("This file contains a secret. Share it with learners out of band; do NOT commit or publish it.")


if __name__ == "__main__":
    main()
