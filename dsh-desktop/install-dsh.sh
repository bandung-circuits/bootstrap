#!/usr/bin/env bash
# dsh-desktop/install-dsh.sh — shared front half for BOTH learner entries
# (public dsh-desktop/setup.sh and dsh-desktop/cohort/cohort-setup.sh):
# ensure the official DeepSeek Harness desktop app is installed.
#
# The OFFICIAL desktop app is "DeepSeek Harness" (deepseek-ai/deepseek-harness,
# apps: apps/desktop), Apple-silicon macOS only (there is no Intel Mac build),
# downloaded from DeepSeek's own CDN. The public download is an always-current
# pointer dsh-latest-macos-arm64.dmg (deepseek.com/download uses the same
# alias), so we cannot pin a versioned URL. We PIN the observed version + the
# dmg sha512 (DSH_VERSION / SHASUM) as an audit record: if a future download no
# longer matches, prep/CI reports it and the pin is bumped deliberately. The
# app's own in-app updater still offers newer versions afterwards and it uses
# the same ~/.dsh data root, so harness config survives upgrades.
#
# This file is the SINGLE SOURCE OF TRUTH for the version pin. Bump
# deliberately, after re-verifying the new dmg: sync the observed
# CFBundleShortVersionString into DSH_VERSION and the dmg sha512 into
# SHASUM_512, keeping this file, install-dsh.ps1 and cohort/generate.py
# agreeing (the cohort smoke checks all three).
# Env-overridable for tests. Run as a child script, never sourced.

set -euo pipefail

# Observed from dsh-latest-macos-arm64.dmg on 2026-09-30 (official DeepSeek CDN):
DSH_VERSION="${DSH_VERSION:-0.2.0-rc.2}"
SHASUM_512="${SHASUM_512:-6b88f10d637ff74461bef5a408223fe349a08cb640034258a57d7c4e6dca4561b27380aeef0318ed8233b9abeb076b77a96cf6a695d757a821b0e8b9efc30237}"
DSH_DMG_URL="${DSH_DMG_URL:-https://download.deepseek.com/desktop/dsh-latest-macos-arm64.dmg}"

note() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# DeepSeek Harness already installed?
APP=""
for p in "/Applications/DeepSeek Harness.app" "${HOME}/Applications/DeepSeek Harness.app"; do
  [ -d "$p" ] && { APP="$p"; break; }
done

if [ -n "$APP" ]; then
  note "DeepSeek Harness already installed: $APP"
  exit 0
fi

# Apple silicon only (no Intel Mac build of the official desktop). sysctl is
# authoritative even when this script runs under Rosetta (`uname -m` would lie).
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
  : # arm64 — the only supported official target
else
  err "DeepSeek Harness 官方桌面版目前只支持 Apple 芯片 Mac（没有 Intel 版）。"
  err "请改用终端里的 npx @deepseek-ai/dsh web，或直接看 https://deepseek.com/harness。"
fi

note "Installing DeepSeek Harness (official) — expected ${DSH_VERSION}, ~353 MB download + a moment to install, one-time"
_TMP="$(mktemp -d)"
cleanup() { [ -n "$_TMP" ] && rm -rf "$_TMP"; return 0; }
trap cleanup EXIT
curl -fL --progress-bar "$DSH_DMG_URL" -o "${_TMP}/dsh.dmg" || err "download failed: $DSH_DMG_URL"

# Optional integrity guard: warn (don't hard-fail) when the always-current
# pointer has moved past the recorded pin — the signal to bump DSH_VERSION.
if command -v shasum >/dev/null 2>&1 && [ "$SHASUM_512" != "" ]; then
  got="$(shasum -a 512 "${_TMP}/dsh.dmg" | awk '{print $1}')"
  if [ "$got" != "$SHASUM_512" ]; then
    note "sha512 of the downloaded build differs from the recorded pin ($DSH_VERSION)"
    note "  expected ${SHASUM_512:0:12}…  got ${got:0:12}…"
    note "  That's expected after a DeepSeek release; prep will verify the installed version."
  else
    note "dmg sha512 matches the pinned ${DSH_VERSION}"
  fi
fi

mnt="$(hdiutil attach "${_TMP}/dsh.dmg" -nobrowse | awk -F'\t' '/Volumes/{print $NF}' | tail -1)" \
  || err "could not mount the DeepSeek Harness disk image"
[ -n "$mnt" ] || err "could not mount the DeepSeek Harness disk image"
src="${mnt}/DeepSeek Harness.app"
[ -d "$src" ] || src="$(find "$mnt" -maxdepth 2 -name 'DeepSeek Harness.app' -type d 2>/dev/null | head -1)"
if [ -z "$src" ]; then
  hdiutil detach "$mnt" -quiet || true
  err "DeepSeek Harness.app not found in the disk image"
fi
dest="/Applications"
if ! ditto "$src" "${dest}/DeepSeek Harness.app" 2>/dev/null; then
  note "no write access to /Applications — installing to ~/Applications instead"
  mkdir -p "${HOME}/Applications"
  dest="${HOME}/Applications"
  ditto "$src" "${dest}/DeepSeek Harness.app" || {
    hdiutil detach "$mnt" -quiet || true
    err "could not copy DeepSeek Harness.app"
  }
fi
hdiutil detach "$mnt" -quiet || true
note "DeepSeek Harness installed: ${dest}/DeepSeek Harness.app"

# Record the version that actually landed (the always-current alias may exceed
# the recorded pin). Warn when it differs so learners aren't surprised.
if [ "$(defaults read "${dest}/DeepSeek Harness.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '')" != "$DSH_VERSION" ]; then
  note "installed version note: the app may be newer than the pinned ${DSH_VERSION}"
fi