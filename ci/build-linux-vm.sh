#!/usr/bin/env bash
# build-linux-vm.sh — runs ON the CI Mac host (after VMware Fusion + qemu are installed
# via ci/host-setup.sh). Builds the Linux ARM template VM from the Ubuntu cloud image,
# boots it with a cloud-init seed so it comes up with user `ci` + our SSH key, waits for
# SSH, then takes the `clean-base` snapshot.
#
# Prereqs: ci/host-setup.sh done (Fusion + qemu-img on PATH). Ubuntu cloud image at
# $UBUNTU_IMG (download it first; see ci/vm-setup.md). Seed ISO at $SEED_ISO.

set -euo pipefail
cd "$(dirname "$0")/.."

note(){ printf '\033[1;32m==>\033[0m %s\n' "$*"; }
err(){ printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

UBUNTU_IMG="${UBUNTU_IMG:-$HOME/vm-images/ubuntu-24.04-server-cloudimg-arm64.img}"
SEED_ISO="${SEED_ISO:-$HOME/vm-work/seed.iso}"
VM_DIR="${VM_DIR:-$HOME/vm-work/linux-arm}"
VMX="$VM_DIR/ci-linux.vmx"
DISK="$VM_DIR/disk.vmdk"
DISK_GB="${DISK_GB:-40}"

[ -f "$UBUNTU_IMG" ] || err "Ubuntu cloud image not found: $UBUNTU_IMG"
[ -f "$SEED_ISO" ]   || err "seed ISO not found: $SEED_ISO"
command -v qemu-img >/dev/null 2>&1 || err "qemu-img not on PATH (run ci/host-setup.sh)"
command -v vmrun   >/dev/null 2>&1 || err "vmrun not on PATH (run ci/host-setup.sh)"

mkdir -p "$VM_DIR"

# 1. Resize the cloud image (qcow2 supports resize; the converted vmdk does not),
#    then convert to a growable vmdk of DISK_GB virtual size.
if [ ! -f "$DISK" ]; then
  note "resizing cloud image to ${DISK_GB}G (cloud image is small; installer needs room)"
  cp "$UBUNTU_IMG" "$VM_DIR/base.qcow2"
  qemu-img resize "$VM_DIR/base.qcow2" "${DISK_GB}G"
  note "converting qcow2 -> vmdk"
  qemu-img convert -f qcow2 -O vmdk -o subformat=monolithicSparse "$VM_DIR/base.qcow2" "$DISK"
  rm -f "$VM_DIR/base.qcow2"
  # root FS is grown to fill the disk over SSH after first boot (below)
fi

# 2. Author the .vmx (arm64 EFI, SATA disk + seed cdrom, NAT, vmxnet3).
note "writing $VMX"
SEED_ISO_ABS="$(cd "$(dirname "$SEED_ISO")" && pwd)/$(basename "$SEED_ISO")"
DISK_ABS="$(cd "$(dirname "$DISK")" && pwd)/$(basename "$DISK")"
cat > "$VMX" <<EOF
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "21"
guestOS = "arm-other-linux-64"
displayName = "ci-linux"
memsize = "4096"
numvcpus = "2"
firmware = "efi"
scsi0.present = "FALSE"
sata0.present = "TRUE"
sata0:0.present = "TRUE"
sata0:0.fileName = "$DISK_ABS"
sata0:1.present = "TRUE"
sata0:1.deviceType = "cdrom-image"
sata0:1.fileName = "$SEED_ISO_ABS"
ethernet0.present = "TRUE"
ethernet0.connectionType = "bridged"
ethernet0.virtualDev = "vmxnet3"
ethernet0.addressType = "generated"
usb.present = "FALSE"
sound.present = "FALSE"
mks.enable3d = "FALSE"
svga.autodetect = "TRUE"
EOF

# 3. Grow root FS on first boot (cloud-init runcmd already in seed grows partition;
#    but cloud image's root is last partition so growpart+resize2fs needed). Append a
#    one-shot runcmd by rebuilding seed is out of scope here; instead we run it over SSH
#    after boot below.

# 4. Start the VM headless.
note "starting VM (headless)"
vmrun -T fusion start "$VMX" nogui 2>/dev/null || vmrun -T fusion start "$VMX"

# 5. Wait for guest IP (needs open-vm-tools, installed by cloud-init) then SSH.
note "waiting for guest IP + SSH"
ip=""
for i in $(seq 1 60); do
  ip=$(vmrun -T fusion getGuestIPAddress "$VMX" 2>/dev/null || true)
  [ -n "$ip" ] && ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no \
      -i "$HOME/vm-work/keys/ci_ed25519" "ci@$ip" 'echo ok' 2>/dev/null | grep -q ok && break
  sleep 5
done
[ -n "$ip" ] || err "could not get guest IP / SSH up in time"
note "VM SSH up at $ip"

# 6. Grow root FS to fill the expanded disk (idempotent).
note "growing root filesystem"
ssh -o StrictHostKeyChecking=no -i "$HOME/vm-work/keys/ci_ed25519" "ci@$ip" \
  'sudo growpart /dev/sda 1 2>/dev/null; sudo resize2fs /dev/sda1 2>/dev/null; df -h / | tail -1' \
  2>&1 | tail -2

# 7. Shut down cleanly, then snapshot clean-base.
note "shutting down for snapshot"
vmrun -T fusion stop "$VMX" soft 2>/dev/null || vmrun -T fusion stop "$VMX" hard
note "taking clean-base snapshot"
vmrun -T fusion snapshot "$VMX" clean-base

# 8. Record the discovered IP as a comment (the NAT lease is usually stable, but
#    run-test.sh resolves IP dynamically via getGuestIPAddress, so this is just a hint).
echo "# ci-linux NAT IP observed at build time: $ip" >> "$VM_DIR/ip-hint.txt"
note "done. VMX=$VMX"
echo "LINUX_VMX=$VMX" > "$VM_DIR/paths.local.hint"
note "add LINUX_VMX=$VMX and LINUX_USER=ci to your .env"
