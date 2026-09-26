#!/usr/bin/env bash
# dsh-desktop/cohort/ci/run-cohort-windows.sh — Windows CI for the cohort
# one-command setup. Runs ON the CI Mac host (yuan), driving the Windows 11 ARM
# VM. Mirrors ci/run-test-dsh-desktop.sh's win leg, with snapshot discipline
# IDENTICAL to the rest of the CI: revert to clean-base -> run -> power off
# (hard, discard). NEVER saves a snapshot over clean-base.
#
# What it tests (the real end-to-end, including the URL-fetch prep path that
# failed on a learner's machine):
#   1. revert Windows VM to clean-base, boot, SSH in.
#   2. run the LATEST committed cohort-setup.ps1 (scp'd in) with a real key:
#      it finds no DSH Desktop on the clean VM, downloads the PINNED release
#      (DSH_VERSION in the script) from GitHub Releases, silent-installs it,
#      then delegates to cohort-prep.ps1 (scp'd in via COHORT_PREP_URL).
#      PREP_URL stays at its default (Pages) so the fixed
#        iex (curl.exe -sL ... | Out-String)
#      branch is exercised. inject_provider.py is scp'd and pointed at via
#      INJECT_URL so the cohort injection uses latest committed code (no Pages
#      lag dependency for the new file).
#   3. verify the cohort injection (verify-cohort-windows.ps1).
#   4. power off (hard) — VM left at clean-base for the next run.
#
# Usage (from the repo root on the CI host, or via ssh yuan):
#   bash dsh-desktop/cohort/ci/run-cohort-windows.sh

set -uo pipefail
cd "$(dirname "$0")/../../.."  # repo root

ENV_FILE=".env"
CI_SSH_KEY="${CI_SSH_KEY:-$HOME/vm-work/keys/ci_ed25519}"
fail(){ printf '\033[1;31m==>\033[0m %s\n' "$*"; exit 1; }
note(){ printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[ -f "$ENV_FILE" ] || fail "missing $ENV_FILE on the CI host — see ci/vm-setup.md"
set -a; source "$ENV_FILE"; set +a
[ -f "$CI_SSH_KEY" ] || fail "CI SSH key not found: $CI_SSH_KEY (for SSHing into the VM)"
[ -n "${WIN_VMX:-}" ] || fail "WIN_VMX not set in .env"
[ -n "${TEST_API_KEY:-}" ] || fail "TEST_API_KEY not set in .env (the cohort key for the smoke)"

mkdir -p ci/logs
stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo manual)
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

note "[cohort/win] revert to clean-base (snapshot discipline: revert only, never save)"
vmrun stop "$WIN_VMX" hard 2>/dev/null || true
vmrun revertToSnapshot "$WIN_VMX" clean-base || fail "windows revert failed"
vmrun start "$WIN_VMX" nogui 2>/dev/null || vmrun start "$WIN_VMX"

note "[cohort/win] resolving guest IP"
ip=$(guest_ip "$WIN_VMX" "${WIN_HOST:-}") || fail "windows: no guest IP"
note "[cohort/win] guest IP: $ip — waiting for SSH"
ssh_wait "$ip" "$WIN_USER" || fail "windows SSH timeout"

note "[cohort/win] scp latest cohort-setup + cohort-prep + inject + verify into VM"
scp -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no \
  dsh-desktop/cohort/cohort-setup.ps1 \
  dsh-desktop/cohort/cohort-prep.ps1 \
  dsh-desktop/cohort/inject_provider.py \
  dsh-desktop/cohort/ci/verify-cohort-windows.ps1 \
  "$WIN_USER@$ip": 2>&1 | tail -1

# the silent installer may auto-launch DSH Desktop; the app's first-run init can
# peg the VM and make SSH time out. Kill it, then re-wait for SSH before prep.
ssh_retry() {
  local n=6
  while [ $n -gt 0 ]; do
    if ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ServerAliveInterval=30 "$WIN_USER@$ip" "$1"; then return 0; fi
    n=$((n-1)); echo "(ssh retry, $n left)"; sleep 15
  done
  return 1
}

note "[cohort/win] guaranteeing the fresh-machine path: remove any DSH Desktop first"
ssh_retry "taskkill /F /IM \"DSH Desktop.exe\" 2>nul& powershell -NoProfile -Command \"Remove-Item -Recurse -Force (Join-Path \$env:LOCALAPPDATA 'Programs\DSH Desktop') -ErrorAction SilentlyContinue; exit 0\"" 2>&1 | tail -1

note "[cohort/win] running cohort-setup.ps1 (pinned DSH Desktop download + install + delegate; DSH_SILENT=1 for the headless VM; PREP_URL=Pages default -> tests the fixed iex|Out-String branch)"
ssh_retry "set TRAINING_API_KEY=$TEST_API_KEY&& set DSH_SILENT=1&& set INJECT_URL=C:\\Users\\$WIN_USER\\inject_provider.py&& set COHORT_PREP_URL=C:\\Users\\$WIN_USER\\cohort-prep.ps1&& powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\$WIN_USER\\cohort-setup.ps1" \
  2>&1 | tee "ci/logs/cohort-win-$stamp.log"
rc=$?
note "[cohort/win] cohort-setup exit: $rc"

note "[cohort/win] verifying the cohort injection"
VERIFY_KEY="$TEST_API_KEY" ssh_retry "set VERIFY_KEY=$TEST_API_KEY&& powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\$WIN_USER\\verify-cohort-windows.ps1" \
  2>&1 | tee -a "ci/logs/cohort-win-$stamp.log"
vrc=$?

# --- launch the app, let it initialize, kill it, then re-check: does the
# injected provider survive the app's first launch? what does workspace.json
# look like? (investigates whether the app overwrites settings.yaml on launch
# and how the active/default workspace is represented) ---
note "[cohort/win] launching DSH Desktop, observing first-launch behavior + workspace preselection"
# 1. launch + wait (app stays running). 2. dump state. 3. screenshot. 4. kill.
ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"\$exe=Join-Path \$env:LOCALAPPDATA 'Programs\DSH Desktop\DSH Desktop.exe'; if (Test-Path \$exe) { Start-Process \$exe; Start-Sleep -Seconds 50; Write-Host '--- settings.yaml (head 60) ---'; Get-Content (Join-Path \$env:APPDATA 'dsh-desktop\harness\settings.yaml') -TotalCount 60 -ErrorAction SilentlyContinue; Write-Host '--- desktop-storage sessions.current ---'; (Get-Content (Join-Path \$env:APPDATA 'dsh-desktop\harness\profiles\web\desktop-storage.json') -Raw -ErrorAction SilentlyContinue); Write-Host '--- workspace.json ---'; Get-Content (Join-Path \$env:APPDATA 'dsh-desktop\harness\storages\workspace.json') -Raw -ErrorAction SilentlyContinue } else { Write-Host 'DSH Desktop.exe not found' }\"" \
  2>&1 | tee -a "ci/logs/cohort-win-$stamp.log"

note "[cohort/win] capturing VM screenshot (app still running)"
SHOT="$HOME/cohort-win-shot.png"
# captureScreen needs guest credentials (VixVM_LoginInGuest).
vmrun -T fusion -gu "$WIN_USER" -gp "${WIN_PASS:-}" captureScreen "$WIN_VMX" "$SHOT" 2>/dev/null \
  || vmrun -gu "$WIN_USER" -gp "${WIN_PASS:-}" captureScreen "$WIN_VMX" "$SHOT" 2>/dev/null || true
ls -la "$SHOT" 2>/dev/null || echo "(no screenshot)"

ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
  "taskkill /F /IM \"DSH Desktop.exe\" 2>nul; exit 0" 2>&1 | tail -1

note "[cohort/win] powering off VM (hard, discard -- leaves clean-base for next run)"
vmrun stop "$WIN_VMX" hard 2>/dev/null || true

note "=== SUMMARY: cohort/windows  cohort-prep=$([ "$rc" = 0 ] && echo PASS || echo FAIL)  verify=$([ "$vrc" = 0 ] && echo PASS || echo FAIL) ==="
[ "$rc" = 0 ] && [ "$vrc" = 0 ]
