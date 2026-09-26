#!/usr/bin/env bash
# dsh-desktop/install-dsh.sh — shared front half for BOTH learner entries
# (public dsh-desktop/setup.sh and dsh-desktop/cohort/cohort-setup.sh):
# ensure DSH Desktop itself is installed.
#
# If the app is missing, downloads the PINNED release (DSH_VERSION below — the
# version the flow is tested against) from the official GitHub Releases and
# installs it without any wizard (mount DMG, copy the app). No admin prompt
# for admin users; standard users get the app in ~/Applications instead.
#
# This file is the SINGLE SOURCE OF TRUTH for the version pin. Bump
# deliberately, after the flow has been verified against the new version (the
# cohort smoke checks the pin agrees with install-dsh.ps1 and generate.py).
# Env-overridable for tests. Run as a child script, never sourced: the two
# learner entries fetch it from Pages (or use the local clone copy), run it,
# then continue with their own delegation step.

set -euo pipefail

DSH_VERSION="${DSH_VERSION:-v0.9.2}"
DSH_RELEASE_BASE="https://github.com/dataelement/dsh-desktop/releases/download/${DSH_VERSION}"

note() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# DSH Desktop present?
APP=""
for p in "/Applications/DSH Desktop.app" "${HOME}/Applications/DSH Desktop.app"; do
  [ -d "$p" ] && { APP="$p"; break; }
done

if [ -n "$APP" ]; then
  note "DSH Desktop already installed: $APP"
  exit 0
fi

# hw.optional.arm64 is authoritative even when this script itself runs under
# Rosetta (where `uname -m` reports x86_64 on Apple Silicon).
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
  dmg="dsh-desktop-mac-arm64.dmg"
else
  dmg="dsh-desktop-mac-x64.dmg"
fi
url="${DSH_RELEASE_BASE}/${dmg}"
note "Installing DSH Desktop ${DSH_VERSION} (${dmg%.dmg}, ~175 MB download + about a minute to install, one-time)"
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
