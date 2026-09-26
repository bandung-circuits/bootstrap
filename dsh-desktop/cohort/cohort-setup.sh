#!/usr/bin/env bash
# dsh-desktop/cohort/cohort-setup.sh — full learner setup for a training cohort
# (macOS). One command, nothing pre-installed:
#
#   curl -fsSL https://bandung-circuits.github.io/bootstrap/dsh-desktop/cohort/cohort-setup.sh \
#     | TRAINING_API_KEY='sk-...' bash
#
# 1. Ensures DSH Desktop is installed: if the app is missing, downloads the
#    PINNED release (DSH_VERSION below — the version the cohort flow is tested
#    against) from the official GitHub Releases and installs it without any
#    wizard (mount DMG, copy the app). No admin prompt for admin users;
#    standard users get the app in ~/Applications instead.
# 2. Delegates everything else to cohort-prep.sh VERBATIM (public prep +
#    provider/key injection), so this script adds no setup logic of its own.
#
# Windows uses cohort-setup.ps1. The public (non-cohort) flow does NOT use this
# script: it still asks learners to install DSH Desktop by hand first.
#
# NOTE on the pin: it only controls what WE install on a fresh machine. The
# app's own auto-updater still offers newer versions afterwards, and harness
# config survives app upgrades — same exposure as the manual-install flow.

set -euo pipefail

REPO_BASE="https://bandung-circuits.github.io/bootstrap"
COHORT_PREP_URL="${COHORT_PREP_URL:-${REPO_BASE}/dsh-desktop/cohort/cohort-prep.sh}"

# Pinned DSH Desktop release. Bump deliberately, after the cohort flow has been
# verified against the new version (see cohort/README.md "Pinned DSH Desktop
# version"). Env-overridable for tests.
DSH_VERSION="${DSH_VERSION:-v0.9.2}"
DSH_RELEASE_BASE="https://github.com/dataelement/dsh-desktop/releases/download/${DSH_VERSION}"

note() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# 0. fail fast on a missing key BEFORE downloading a ~176 MB installer.
: "${TRAINING_API_KEY:?TRAINING_API_KEY is missing — copy the command from your cohort page, not a generic one.}"

# 1. DSH Desktop present?
APP=""
for p in "/Applications/DSH Desktop.app" "${HOME}/Applications/DSH Desktop.app"; do
  [ -d "$p" ] && { APP="$p"; break; }
done

if [ -n "$APP" ]; then
  note "DSH Desktop already installed: $APP"
else
  # hw.optional.arm64 is authoritative even when this script itself runs under
  # Rosetta (where `uname -m` reports x86_64 on Apple Silicon).
  if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
    dmg="dsh-desktop-mac-arm64.dmg"
  else
    dmg="dsh-desktop-mac-x64.dmg"
  fi
  url="${DSH_RELEASE_BASE}/${dmg}"
  note "Installing DSH Desktop ${DSH_VERSION} (${dmg%.dmg}, ~175 MB, one-time)"
  _TMP="$(mktemp -d)"
  cleanup() { [ -n "$_TMP" ] && rm -rf "$_TMP"; return 0; }
  trap cleanup EXIT
  curl -fL --progress-bar "$url" -o "${_TMP}/dsh.dmg" || err "download failed: $url"
  mnt="$(hdiutil attach "${_TMP}/dsh.dmg" -nobrowse | awk -F'\t' '/Volumes/{print $NF}' | tail -1)" \
    || err "could not mount the DSH Desktop disk image"
  [ -n "$mnt" ] || err "could not mount the DSH Desktop disk image"
  src="${mnt}/DSH Desktop.app"
  [ -d "$src" ] || src="$(find "$mnt" -maxdepth 2 -name 'DSH Desktop.app' -type d 2>/dev/null | head -1)"
  if [ -z "$src" ]; then
    hdiutil detach "$mnt" -quiet || true
    err "DSH Desktop.app not found in the disk image"
  fi
  dest="/Applications"
  if ! ditto "$src" "${dest}/DSH Desktop.app" 2>/dev/null; then
    note "no write access to /Applications — installing to ~/Applications instead"
    mkdir -p "${HOME}/Applications"
    dest="${HOME}/Applications"
    ditto "$src" "${dest}/DSH Desktop.app" || {
      hdiutil detach "$mnt" -quiet || true
      err "could not copy DSH Desktop.app"
    }
  fi
  hdiutil detach "$mnt" -quiet || true
  note "DSH Desktop installed: ${dest}/DSH Desktop.app"
fi

# 2. everything else is exactly the existing cohort flow (public prep + inject).
# REUSE — no setup logic here. Env (key, model, …) flows through to the child.
note "Running the cohort workspace setup (workspace, web tools, model provider)"
if [ -f "$COHORT_PREP_URL" ]; then
  bash "$COHORT_PREP_URL"
else
  curl -fsSL "$COHORT_PREP_URL" | bash
fi
