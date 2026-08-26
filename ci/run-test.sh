#!/usr/bin/env bash
# run-test.sh — runs ON the CI Mac host.
# Reverts each VM to clean-base, boots, resolves its IP via vmrun, SSHes in to run
# the installer + verify, then reports PASS/FAIL for Linux and Windows. Unattended.
#
# Prereqs: see ci/vm-setup.md. Needs .env (gitignored) at the repo root with VM
# paths + test API key — copy .env.example to .env. VM IPs are resolved
# dynamically via `vmrun getGuestIPAddress` (guest must have VMware Tools /
# open-vm-tools), so .env LINUX_HOST/WIN_HOST are only fallback hints.

set -uo pipefail
cd "$(dirname "$0")/.."

REPO_RAW="https://bandung-circuits.github.io/bootstrap"
INSTALL_URL="${REPO_RAW}/install.sh"
PS1_URL="${REPO_RAW}/install.ps1"

ENV_FILE=".env"
# Path to the CI SSH key created by build-linux-vm.sh (override in .env if needed).
CI_SSH_KEY="${CI_SSH_KEY:-$HOME/vm-work/keys/ci_ed25519}"

fail(){ printf '\033[1;31m==>\033[0m %s\n' "$*"; exit 1; }
note(){ printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[ -f "$ENV_FILE" ] || fail "missing $ENV_FILE — copy .env.example to .env (see ci/vm-setup.md)"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
[ -f "$CI_SSH_KEY" ] || fail "CI SSH key not found: $CI_SSH_KEY"

mkdir -p ci/logs
stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "manual")

export PATH="$PATH:/Applications/VMware Fusion.app/Contents/Public"
vmrun(){ command vmrun -T fusion "$@"; }

# Resolve a VM's guest IP: try vmrun getGuestIPAddress (only accept a real dotted-quad),
# fall back to the .env hint.
guest_ip(){
  local vmx="$1" hint="$2" ip
  for i in $(seq 1 30); do
    ip=$(vmrun getGuestIPAddress "$vmx" 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$" || true)
    [ -n "$ip" ] && { echo "$ip"; return 0; }
    sleep 5
  done
  [ -n "$hint" ] && { echo "$hint"; return 0; }
  return 1
}
ssh_wait(){
  local host="$1" user="$2" tries=40
  until ssh -i "$CI_SSH_KEY" -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$user@$host" 'echo ok' 2>/dev/null | grep -q ok; do
    tries=$((tries-1)); [ "$tries" -le 0 ] && return 1; sleep 5
  done
}

# ---------- Linux ----------
test_linux(){
  note "[Linux] revert to clean-base"
  vmrun revertToSnapshot "$LINUX_VMX" clean-base || fail "revert linux failed"
  vmrun start "$LINUX_VMX" nogui 2>/dev/null || vmrun start "$LINUX_VMX"
  note "[Linux] resolving guest IP"
  local ip; ip=$(guest_ip "$LINUX_VMX" "${LINUX_HOST:-}") || fail "linux: no guest IP"
  note "[Linux] guest IP: $ip — waiting for SSH"
  ssh_wait "$ip" "$LINUX_USER" || fail "linux SSH timeout"
  note "[Linux] rsync repo into VM (test latest committed code, no Pages CDN)"
  rsync -az -e "ssh -i $CI_SSH_KEY -o StrictHostKeyChecking=no" \
    --exclude ".git" --exclude "ci/logs" \
    "$(pwd)/" "$LINUX_USER@$ip":~/bootstrap/ 2>&1 | tail -1
  note "[Linux] running installer from clone (local lib)"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$LINUX_USER@$ip" \
    "cd ~/bootstrap && bash install.sh --provider=$TEST_PROVIDER --api-key=$TEST_API_KEY" \
    2>&1 | tee "ci/logs/linux-install-$stamp.log"
  note "[Linux] verifying"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$LINUX_USER@$ip" \
    "TEST_PROVIDER=$TEST_PROVIDER TEST_API_KEY=$TEST_API_KEY bash ~/bootstrap/ci/verify/verify-linux.sh" \
    2>&1 | tee "ci/logs/linux-verify-$stamp.log"
}

# ---------- Windows ----------
test_windows(){
  note "[Windows] revert to clean-base"
  vmrun revertToSnapshot "$WIN_VMX" clean-base || fail "revert windows failed"
  vmrun start "$WIN_VMX" nogui 2>/dev/null || vmrun start "$WIN_VMX"
  note "[Windows] resolving guest IP"
  local ip; ip=$(guest_ip "$WIN_VMX" "${WIN_HOST:-}") || fail "windows: no guest IP"
  note "[Windows] guest IP: $ip — waiting for SSH"
  ssh_wait "$ip" "$WIN_USER" || fail "windows SSH timeout"
  note "[Windows] scp install.ps1 + verify-windows.ps1 into VM"
  scp -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no install.ps1 ci/verify/verify-windows.ps1 "$WIN_USER@$ip": 2>&1 | tail -1
  note "[Windows] running installer (with provider + key)"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
    "powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Provider $TEST_PROVIDER -ApiKey $TEST_API_KEY" \
    2>&1 | tee "ci/logs/win-install-$stamp.log"
  note "[Windows] verifying"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
    "set TEST_PROVIDER=$TEST_PROVIDER&& set TEST_API_KEY=$TEST_API_KEY&& powershell -NoProfile -ExecutionPolicy Bypass -File verify-windows.ps1" \
    2>&1 | tee "ci/logs/win-verify-$stamp.log"
}

note "=== Bootstrap CI run $stamp ==="
# ensure the host repo is current (tests latest committed code)
git pull -q --ff-only origin main 2>/dev/null || note "(git pull skipped/failed — using current tree)"

test_linux  ; lr=${PIPESTATUS[0]:-$?}
if [ -n "${WIN_VMX:-}" ]; then
  test_windows; wr=${PIPESTATUS[0]:-$?}
else
  note "[Windows] skipped (WIN_VMX not set in .env)"
  wr=0
fi
echo
note "=== SUMMARY: Linux=$([ $lr -eq 0 ] && echo PASS || echo FAIL)  Windows=$([ $wr -eq 0 ] && echo PASS || echo FAIL) ==="
[ $lr -eq 0 ] && [ $wr -eq 0 ]
