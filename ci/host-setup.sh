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
while [ $# -gt 0 ]; do
  case "$1" in
    --fusion-dmg) FUSION_DMG="$2"; shift 2 ;;
    --fusion-dmg=*) FUSION_DMG="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,14p' "$0"; exit 0 ;;
    *) err "unknown argument: $1" ;;
  esac
done

[ "$(uname -m)" = "arm64" ] || err "this script targets Apple Silicon (arm64)."

# ---------- Homebrew ----------
# brew may be installed but not on a non-login shell PATH; source its shellenv.
if ! command -v brew >/dev/null 2>&1; then
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi
if ! command -v brew >/dev/null 2>&1; then
  note "Installing Homebrew (will ask for sudo password)"
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # shellcheck disable=SC2016
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  note "Homebrew already installed ($(brew --version | head -1))"
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
  # The dmg ships "VMware Fusion.app"; the deployable metapackage lives inside it.
  MPKG=$(find /tmp/fusionmnt -maxdepth 4 -iname "Deploy VMware Fusion.mpkg" | head -1 || true)
  [ -n "$MPKG" ] || MPKG=$(find /tmp/fusionmnt -maxdepth 3 -iname "*.pkg" | head -1 || true)
  [ -n "$MPKG" ] || err "no Deploy VMware Fusion.mpkg found in dmg; mount: /tmp/fusionmnt"
  note "Installing Fusion via metapackage (sudo): $MPKG"
  sudo installer -pkg "$MPKG" -target /
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
