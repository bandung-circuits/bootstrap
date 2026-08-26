#!/usr/bin/env bash
# make-clean-base.sh — turn a freshly-installed Ubuntu VM into the CI clean-base
# baseline, SAFELY. Runs on the CI host (yuan). Idempotent.
#
# Root cause this prevents: re-snapshotting a DIRTY (already-installed) state and
# baking it into clean-base. This script ASSERTS the VM is clean (no VS Code, no
# ai-workspace, no .bootstrap) BEFORE snapshotting, and aborts if not — so a dirty
# state can never become the baseline.
#
# Prereqs on the fresh VM (manual, by the user):
#   - Ubuntu Server (ARM64) installed, with OpenSSH server + a user account.
# Reads VM_IP / VM_USER / VM_PASS / VM_VMX from .env (or args below).
#
# Usage: bash ci/make-clean-base.sh [VM_IP] [VM_USER] [VM_PASS] [VM_VMX]

set -euo pipefail
cd "$(dirname "$0")/.."

note(){ printf '\033[1;32m==>\033[0m %s\n' "$*"; }
err(){ printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# load .env if present, allow arg overrides
VM_IP="${1:-${LINUX_HOST:-}}"
VM_USER="${2:-${LINUX_USER:-}}"
VM_PASS="${3:-${LINUX_PASS:-}}"
VM_VMX="${4:-${LINUX_VMX:-}}"
[ -f .env ] && { set -a; source .env; set +a; }
VM_IP="${VM_IP:-$LINUX_HOST}"; VM_USER="${VM_USER:-$LINUX_USER}"
VM_PASS="${VM_PASS:-$LINUX_PASS}"; VM_VMX="${VM_VMX:-$LINUX_VMX}"
CI_SSH_KEY="${CI_SSH_KEY:-$HOME/vm-work/keys/ci_ed25519}"

[ -n "$VM_IP" ]  || err "VM_IP missing (arg1 or LINUX_HOST in .env)"
[ -n "$VM_USER" ]|| err "VM_USER missing (arg2 or LINUX_USER in .env)"
[ -n "$VM_PASS" ]|| err "VM_PASS missing (arg3 or LINUX_PASS in .env)"
[ -n "$VM_VMX" ] || err "VM_VMX missing (arg4 or LINUX_VMX in .env)"
[ -f "$CI_SSH_KEY" ] || err "CI SSH key not found: $CI_SSH_KEY"

export PATH="$PATH:/Applications/VMware Fusion.app/Contents/Public"

# ---------- 1. add CI pubkey (password auth via expect) ----------
PUB=$(cat "$CI_SSH_KEY.pub")
note "adding CI pubkey to $VM_USER@$VM_IP"
cat > /tmp/mcb_addkey.exp <<EXP
#!/usr/bin/expect -f
set timeout 30
spawn ssh -o StrictHostKeyChecking=accept-new $VM_USER@$VM_IP "mkdir -p ~/.ssh && echo '$PUB' >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && echo KEYADDED"
expect {
  -re "assword:" { send "$VM_PASS\r"; exp_continue }
  "KEYADDED" { }
  eof { }
  timeout { puts TIMEOUT; exit 1 }
}
EXP
chmod +x /tmp/mcb_addkey.exp
/tmp/mcb_addkey.exp >/dev/null 2>&1 || err "failed to add CI pubkey"
note "CI pubkey added"

# ---------- 2. enable passwordless sudo for the CI user ----------
note "enabling passwordless sudo"
ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" \
  "cat > /tmp/sudoers-ci" <<EOF
$VM_USER ALL=(ALL) NOPASSWD: ALL
EOF
ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" \
  "echo '$VM_PASS' | sudo -S cp /tmp/sudoers-ci /etc/sudoers.d/$VM_USER && echo '$VM_PASS' | sudo -S chmod 0440 /etc/sudoers.d/$VM_USER && sudo -n true && echo SUDO_OK" \
  | grep -q SUDO_OK || err "passwordless sudo failed"

# ---------- 3. install open-vm-tools + open-vm-tools-desktop ----------
note "installing open-vm-tools + open-vm-tools-desktop"
ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" \
  'sudo apt-get update -qq && sudo apt-get install -y open-vm-tools open-vm-tools-desktop >/dev/null 2>&1; systemctl is-active open-vm-tools' \
  | grep -q active || err "open-vm-tools not active"

# ---------- 4. host: disable 3D in vmx (fixes blank screen on resume) ----------
note "disabling 3D acceleration in vmx"
grep -q 'mks.enable3d' "$VM_VMX" || echo 'mks.enable3d = "FALSE"' >> "$VM_VMX"

# ---------- 5. SAFETY: assert VM is CLEAN before snapshotting ----------
note "verifying VM is clean (no installed bootstrap artifacts)..."
ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" '
  fail=0
  command -v code >/dev/null 2>&1 && { echo "  DIRTY: VS Code (code) is installed"; fail=1; }
  [ -d "$HOME/ai-workspace" ] && { echo "  DIRTY: ~/ai-workspace exists"; fail=1; }
  [ -d "$HOME/.bootstrap" ] && { echo "  DIRTY: ~/.bootstrap exists"; fail=1; }
  [ -d "$HOME/.claude" ] && { echo "  DIRTY: ~/.claude exists"; fail=1; }
  exit $fail
' || err "VM is DIRTY — NOT snapshotting. Reinstall the VM (or clean it) before re-running. This guard prevents baking a dirty state into clean-base."
note "VM is clean ✓"

# ---------- 6. shut down + snapshot clean-base ----------
note "shutting down VM for snapshot"
vmrun -T fusion stop "$VM_VMX" soft 2>/dev/null || vmrun -T fusion stop "$VM_VMX" hard
# remove any old clean-base so we retake a fresh one
vmrun -T fusion listSnapshots "$VM_VMX" 2>/dev/null | grep -q clean-base \
  && vmrun -T fusion deleteSnapshot "$VM_VMX" clean-base 2>/dev/null || true
note "taking clean-base snapshot"
vmrun -T fusion snapshot "$VM_VMX" clean-base
vmrun -T fusion listSnapshots "$VM_VMX"

note "Done. clean-base is a verified-clean baseline (openssh + open-vm-tools + open-vm-tools-desktop + CI key + passwordless sudo, 3D off, nothing else)."
