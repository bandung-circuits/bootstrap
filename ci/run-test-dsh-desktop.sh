#!/usr/bin/env bash
# run-test-dsh-desktop.sh — CI for the DSH Desktop prep path. Runs ON the CI
# Mac host:
#   * mac leg:  dsh-desktop/ci/verify/verify-macos.sh (isolated prep + compose)
#   * win leg:  Windows VM — install DSH Desktop, run prep.ps1, verify.
#
# Usage: bash ci/run-test-dsh-desktop.sh
# Prereqs identical to run-test.sh (see ci/vm-setup.md + .env).

set -uo pipefail
cd "$(dirname "$0")/.."

ENV_FILE=".env"
CI_SSH_KEY="${CI_SSH_KEY:-$HOME/vm-work/keys/ci_ed25519}"
fail(){ printf '\033[1;31m==>\033[0m %s\n' "$*"; exit 1; }
note(){ printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[ -f "$ENV_FILE" ] || fail "missing $ENV_FILE — copy .env.example to .env"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
[ -f "$CI_SSH_KEY" ] || fail "CI SSH key not found: $CI_SSH_KEY"

mkdir -p ci/logs
stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "manual")
export PATH="$PATH:/Applications/VMware Fusion.app/Contents/Public"
vmrun(){ command vmrun -T fusion "$@"; }

guest_ip(){
  local vmx="$1" hint="$2" ip
  for i in $(seq 1 30); do
    ip=$(vmrun getGuestIPAddress "$vmx" 2>/dev/null | grep -E "^[0-9.]+$" || true)
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

mac_rc=""; win_rc=""

# ---------- mac leg (host) ----------
note "[mac] verifying prep (isolated) + bundled compose"
if bash dsh-desktop/ci/verify/verify-macos.sh 2>&1 | tee "ci/logs/dshdesktop-mac-$stamp.log"; then
  mac_rc=0
else
  mac_rc=1
fi

# ---------- win leg (VM) ----------
if [ -n "${WIN_VMX:-}" ]; then
  note "[win] revert to clean-base"
  vmrun stop "$WIN_VMX" hard 2>/dev/null || true
  vmrun revertToSnapshot "$WIN_VMX" clean-base || fail "windows revert failed"
  vmrun start "$WIN_VMX" nogui 2>/dev/null || vmrun start "$WIN_VMX"
  ip=$(guest_ip "$WIN_VMX" "${WIN_HOST:-}") || fail "windows: no guest IP"
  note "[win] guest IP: $ip — waiting for SSH"
  ssh_wait "$ip" "$WIN_USER" || fail "windows SSH timeout"
  note "[win] scp CI-internal scripts into VM"
  scp -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no \
    dsh-desktop/ci/install-windows.ps1 dsh-desktop/ci/verify/verify-windows.ps1 "$WIN_USER@$ip": 2>&1 | tail -1
  note "[win] installing DSH Desktop (if needed)"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
    "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/$WIN_USER/install-windows.ps1" \
    2>&1 | tail -3
  note "[win] running prep via REAL user path: irm | iex (fetches from Pages)"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
    "powershell -NoProfile -ExecutionPolicy Bypass -Command \"irm https://bandung-circuits.github.io/bootstrap/dsh-desktop/prep.ps1 | iex\"" \
    2>&1 | tail -10
  note "[win] verifying"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
    "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/$WIN_USER/verify-windows.ps1" \
    2>&1 | tee "ci/logs/dshdesktop-win-$stamp.log"
  win_rc=$?
  note "[win] powering off VM"
  vmrun stop "$WIN_VMX" hard 2>/dev/null || true
else
  note "[win] skipped (WIN_VMX not set)"
  win_rc=0
fi

echo
note "=== SUMMARY: dsh-desktop  macOS=$([ "$mac_rc" = 0 ] && echo PASS || echo FAIL)  Windows=$([ "$win_rc" = 0 ] && echo PASS || echo FAIL) ==="
[ "$mac_rc" = 0 ] && [ "$win_rc" = 0 ]