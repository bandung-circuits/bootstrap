#!/usr/bin/env bash
# host-setup.sh — one-shot setup of the CI host (an Apple Silicon Mac).
# Installs Homebrew, qemu (for image conversion), and VMware Fusion Pro.
#
# Run on the Mac host:
#   ./ci/host-setup.sh --fusion-dmg /path/to/VMware-Fusion-Pro.dmg
#
# Needs sudo (Homebrew + Fusion .pkg install). You'll be prompted once.
# The Fusion dmg must be downloaded by you from your Broadcom account:
#   https://software.broadcom.com/products/vmware-fusion
# (VMware Fusion Pro is free for personal use; requires a free Broadcom account.)

set -euo pipefail
note(){ printf '\033[1;32m==>\033[0m %s\n' "$*"; }
err(){ printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

FUSION_DMG=""
for a in "$@"; do
  case "$a" in
    --fusion-dmg=*) FUSION_DMG="${a#*=}" ;;
    -h|--help)
      sed -n '2,14p' "$0"; exit 0 ;;
    *) err "unknown arg: $a" ;;
  esac
done

[ "$(uname -m)" = "arm64" ] || err "this script targets Apple Silicon (arm64)."

# ---------- Homebrew ----------
if ! command -v brew >/dev/null 2>&1; then
  note "Installing Homebrew (will ask for sudo password)"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # shellcheck disable=SC2016
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  note "Homebrew already installed"
fi

# ---------- qemu (qemu-img for qcow2 -> vmdk) ----------
note "Installing qemu (for cloud-image conversion)"
brew install qemu

# ---------- VMware Fusion Pro ----------
if [ -z "$FUSION_DMG" ]; then
  err "no --fusion-dmg given. Download VMware Fusion Pro from your Broadcom account, then rerun with --fusion-dmg=/path/to/it.dmg"
fi
[ -f "$FUSION_DMG" ] || err "dmg not found: $FUSION_DMG"

if [ ! -d "/Applications/VMware Fusion.app" ]; then
  note "Mounting Fusion dmg"
  hdiutil attach "$FUSION_DMG" -nobrowse -mountpoint /tmp/fusionmnt
  # find the .pkg inside the mounted volume
  PKG=$(find /tmp/fusionmnt -maxdepth 2 -name "*.pkg" | head -1 || true)
  [ -n "$PKG" ] || err "no .pkg found in the dmg; mount point: /tmp/fusionmnt"
  note "Installing Fusion (will use sudo): $PKG"
  sudo installer -pkg "$PKG" -target /
  hdiutil detach /tmp/fusionmnt
else
  note "VMware Fusion already installed"
fi

# ---------- expose vmrun on PATH ----------
FUSION_BIN="/Applications/VMware Fusion.app/Contents/Public"
if ! grep -q "VMware Fusion" ~/.zprofile 2>/dev/null; then
  echo "export PATH=\"\$PATH:$FUSION_BIN\"" >> ~/.zprofile
fi
export PATH="$PATH:$FUSION_BIN"

note "Done. Verify:"
command vmrun -T fusion list 2>&1 | head
command qemu-img --version | head -1
