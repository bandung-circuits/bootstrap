#!/usr/bin/env bash
# run-test.sh — runs ON the CI Mac host.
# Reverts each VM to clean-base, boots, resolves its IP via vmrun, SSHes in to run
# the installer + verify, then reports PASS/FAIL per scheme for Linux + Windows.
# Each scheme gets its own clean snapshot (both write ~/ai-workspace).
#
# Prereqs: see ci/vm-setup.md. Needs .env (gitignored) at the repo root with VM
# paths + test API key — copy .env.example to .env. VM IPs are resolved
# dynamically via `vmrun getGuestIPAddress` (guest must have VMware Tools /
# open-vm-tools), so .env LINUX_HOST/WIN_HOST are only fallback hints.
#
# Schemes that only run on Windows (DSH Desktop has no Linux build) can set
# SCHEMES_LINUX_ONLY=0 per entry below.

set -uo pipefail
cd "$(dirname "$0")/.."

# scheme dirs containing install.sh + ci/verify (vscode runs everywhere;
# dsh-desktop is Windows-only, added when its Windows leg is ready).
SCHEMES=(vscode)

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

# Run one scheme end-to-end on the Linux VM (fresh clean-base for each scheme).
test_linux_scheme(){
  local scheme="$1" vmx="$LINUX_VMX" host="${LINUX_HOST:-}" user="$LINUX_USER"
  note "[Linux/$scheme] revert to clean-base"
  # Ensure the VM is powered off first — a prior run may have left it on,
  # and vmrun revertToSnapshot on a powered-on VM fails ("Unknown error").
  vmrun stop "$vmx" hard 2>/dev/null || true
  vmrun revertToSnapshot "$vmx" clean-base || fail "revert linux failed ($scheme)"
  vmrun start "$vmx" nogui 2>/dev/null || vmrun start "$vmx"
  note "[Linux/$scheme] resolving guest IP"
  local ip; ip=$(guest_ip "$vmx" "$host") || fail "linux: no guest IP ($scheme)"
  note "[Linux/$scheme] guest IP: $ip — waiting for SSH"
  ssh_wait "$ip" "$user" || fail "linux SSH timeout ($scheme)"
  note "[Linux/$scheme] rsync repo into VM (test latest committed code, no Pages CDN)"
  rsync -az -e "ssh -i $CI_SSH_KEY -o StrictHostKeyChecking=no" \
    --exclude ".git" --exclude "ci/logs" \
    "$(pwd)/" "$user@$ip":~/bootstrap/ 2>&1 | tail -1
  note "[Linux/$scheme] running installer from clone (local lib+templates)"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$user@$ip" \
    "cd ~/bootstrap && BOOTSTRAP_NO_LAUNCH=1 bash $scheme/install.sh --provider=$TEST_PROVIDER --api-key=$TEST_API_KEY" \
    2>&1 | tee "ci/logs/${scheme}-linux-install-$stamp.log"
  note "[Linux/$scheme] verifying"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$user@$ip" \
    "TEST_PROVIDER=$TEST_PROVIDER TEST_API_KEY=$TEST_API_KEY bash ~/bootstrap/$scheme/ci/verify/verify-linux.sh" \
    2>&1 | tee "ci/logs/${scheme}-linux-verify-$stamp.log"
  local rc=$?
  note "[Linux/$scheme] powering off VM (leave clean for next run)"
  vmrun stop "$vmx" hard 2>/dev/null || true
  return $rc
}

# Run one scheme on the Windows VM (fresh clean-base; only when WIN_VMX set).
test_windows_scheme(){
  local scheme="$1" vmx="$WIN_VMX" host="${WIN_HOST:-}" user="$WIN_USER"
  note "[Win/$scheme] revert to clean-base"
  vmrun stop "$vmx" hard 2>/dev/null || true
  vmrun revertToSnapshot "$vmx" clean-base || fail "revert windows failed ($scheme)"
  vmrun start "$vmx" nogui 2>/dev/null || vmrun start "$vmx"
  note "[Win/$scheme] resolving guest IP"
  local ip; ip=$(guest_ip "$vmx" "$host") || fail "windows: no guest IP ($scheme)"
  note "[Win/$scheme] guest IP: $ip — waiting for SSH"
  ssh_wait "$ip" "$user" || fail "windows SSH timeout ($scheme)"
  note "[Win/$scheme] scp installer + verify into VM"
  scp -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no \
    "$scheme/install.ps1" "$scheme/ci/verify/verify-windows.ps1" "$user@$ip": 2>&1 | tail -1
  note "[Win/$scheme] running installer (with provider + key)"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$user@$ip" \
    "set BOOTSTRAP_NO_LAUNCH=1&& powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Provider $TEST_PROVIDER -ApiKey $TEST_API_KEY" \
    2>&1 | tee "ci/logs/${scheme}-win-install-$stamp.log"
  note "[Win/$scheme] verifying"
  ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$user@$ip" \
    "set TEST_PROVIDER=$TEST_PROVIDER&& set TEST_API_KEY=$TEST_API_KEY&& powershell -NoProfile -ExecutionPolicy Bypass -File verify-windows.ps1" \
    2>&1 | tee "ci/logs/${scheme}-win-verify-$stamp.log"
  local rc=$?
  note "[Win/$scheme] powering off VM (leave clean for next run)"
  vmrun stop "$vmx" hard 2>/dev/null || true
  return $rc
}

note "=== Bootstrap CI run $stamp ==="
# ensure the host repo is current (tests latest committed code)
git pull -q --ff-only origin main 2>/dev/null || note "(git pull skipped/failed — using current tree)"

# Results as plain vars — macOS system bash is 3.2 and has no associative arrays.
linux_rc="" ; win_rc=""
for scheme in "${SCHEMES[@]}"; do
  if [ -n "${LINUX_VMX:-}" ] && [ -f "$scheme/install.sh" ]; then
    test_linux_scheme "$scheme"; linux_rc="$linux_rc $scheme:$?"
  else
    note "[Linux/$scheme] skipped (no Linux entry / no LINUX_VMX)"
    linux_rc="$linux_rc $scheme:0"
  fi
  if [ -n "${WIN_VMX:-}" ] && [ -f "$scheme/install.ps1" ]; then
    test_windows_scheme "$scheme"; win_rc="$win_rc $scheme:$?"
  else
    note "[Win/$scheme] skipped (no Windows entry / no WIN_VMX in .env)"
    win_rc="$win_rc $scheme:0"
  fi
done

echo
for scheme in "${SCHEMES[@]}"; do
  lr=$(printf '%s\n' "$linux_rc" | tr ' ' '\n' | awk -F: -v s="$scheme" '$1==s{print $2; exit}')
  wr=$(printf '%s\n' "$win_rc"   | tr ' ' '\n' | awk -F: -v s="$scheme" '$1==s{print $2; exit}')
  note "=== SUMMARY: $scheme  Linux=$([ "$lr" = 0 ] && echo PASS || echo FAIL)  Windows=$([ "$wr" = 0 ] && echo PASS || echo FAIL) ==="
done
final=0
for s in $linux_rc $win_rc; do
  rc="${s#*:}"; [ "$rc" != 0 ] && final=1
done
exit $final