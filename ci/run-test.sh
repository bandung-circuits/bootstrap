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

# Resolve a VM's guest IP: try vmrun getGuestIPAddress, fall back to .env hint.
guest_ip(){
  local vmx="$1" hint="$2" ip
  for i in $(seq 1 30); do
    ip=$(vmrun getGuestIPAddress "$vmx" 2>/dev/null || true)
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
  note "[Linux] running installer"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$LINUX_USER@$ip" \
    "curl -fsSL $INSTALL_URL | bash -s -- --provider=$TEST_PROVIDER --api-key=$TEST_API_KEY" \
    2>&1 | tee "ci/logs/linux-install-$stamp.log"
  note "[Linux] verifying"
  scp -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no ci/verify/verify-linux.sh "$LINUX_USER@$ip":/tmp/verify.sh
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$LINUX_USER@$ip" \
    "TEST_PROVIDER=$TEST_PROVIDER TEST_API_KEY=$TEST_API_KEY bash /tmp/verify.sh" \
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
  note "[Windows] running installer (PowerShell)"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
    "powershell -NoProfile -Command \"irm $PS1_URL | iex\"" \
    2>&1 | tee "ci/logs/win-install-$stamp.log"
  note "[Windows] verifying"
  scp -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no ci/verify/verify-windows.ps1 "$WIN_USER@$ip":verify.ps1
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
    "powershell -NoProfile -Command \"\$env:TEST_PROVIDER='$TEST_PROVIDER'; \$env:TEST_API_KEY='$TEST_API_KEY'; .\verify.ps1\"" \
    2>&1 | tee "ci/logs/win-verify-$stamp.log"
}

note "=== Bootstrap CI run $stamp ==="
test_linux  ; lr=${PIPESTATUS[0]:-$?}
test_windows; wr=${PIPESTATUS[0]:-$?}
echo
note "=== SUMMARY: Linux=$([ $lr -eq 0 ] && echo PASS || echo FAIL)  Windows=$([ $wr -eq 0 ] && echo PASS || echo FAIL) ==="
[ $lr -eq 0 ] && [ $wr -eq 0 ]
