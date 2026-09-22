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
#   2. install DSH Desktop (reuse dsh-desktop/ci/install-windows.ps1).
#   3. run the LATEST committed cohort-prep.ps1 (scp'd in) with a real key.
#      PREP_URL is left at its default (Pages) so the fixed
#        iex (curl.exe -sL ... | Out-String)
#      branch is exercised. inject_provider.py is scp'd and pointed at via
#      INJECT_URL so the cohort injection uses latest committed code (no Pages
#      lag dependency for the new file).
#   4. verify the cohort injection (verify-cohort-windows.ps1).
#   5. power off (hard) — VM left at clean-base for the next run.
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

note "[cohort/win] scp latest cohort + inject + install + verify into VM"
scp -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no \
  dsh-desktop/cohort/cohort-prep.ps1 \
  dsh-desktop/cohort/inject_provider.py \
  dsh-desktop/ci/install-windows.ps1 \
  dsh-desktop/cohort/ci/verify-cohort-windows.ps1 \
  "$WIN_USER@$ip": 2>&1 | tail -1

note "[cohort/win] installing DSH Desktop (if not already)"
ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
  "powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/$WIN_USER/install-windows.ps1" \
  2>&1 | tail -3

# DSH Desktop must be quit before cohort-prep writes its config. The silent
# install above does not launch the app, but kill any stray process just in case.
ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
  "taskkill /F /IM 'DSH Desktop.exe' 2>nul; exit 0" 2>&1 | tail -1

note "[cohort/win] running cohort-prep.ps1 (PREP_URL=Pages default -> tests the fixed iex|Out-String branch)"
ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
  "set TRAINING_API_KEY=$TEST_API_KEY&& set INJECT_URL=C:\\Users\\$WIN_USER\\inject_provider.py&& powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\$WIN_USER\\cohort-prep.ps1" \
  2>&1 | tee "ci/logs/cohort-win-$stamp.log"
rc=$?
note "[cohort/win] cohort-prep exit: $rc"

note "[cohort/win] verifying the cohort injection"
VERIFY_KEY="$TEST_API_KEY" ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
  "set VERIFY_KEY=$TEST_API_KEY&& powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\$WIN_USER\\verify-cohort-windows.ps1" \
  2>&1 | tee -a "ci/logs/cohort-win-$stamp.log"
vrc=$?

# --- launch the app, let it initialize, kill it, then re-check: does the
# injected provider survive the app's first launch? what does workspace.json
# look like? (investigates whether the app overwrites settings.yaml on launch
# and how the active/default workspace is represented) ---
note "[cohort/win] pre-registering ai-workspace in workspace.json (EXPERIMENT)"
scp -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no \
  dsh-desktop/cohort/ci/register-workspace.ps1 "$WIN_USER@$ip": 2>&1 | tail -1
ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
  "powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\$WIN_USER\\register-workspace.ps1" \
  2>&1 | tee -a "ci/logs/cohort-win-$stamp.log"

note "[cohort/win] launching DSH Desktop once, then re-checking survival + workspace state"
ssh -i "$CI_SSH_KEY" -o StrictHostKeyChecking=no "$WIN_USER@$ip" \
  "powershell -NoProfile -ExecutionPolicy Bypass -Command \"\$exe=Join-Path \$env:LOCALAPPDATA 'Programs\DSH Desktop\DSH Desktop.exe'; if (Test-Path \$exe) { Start-Process \$exe; Start-Sleep -Seconds 45; Get-Process | Where-Object { \$_.ProcessName -match 'DSH\s*Desktop' } | Stop-Process -Force; Start-Sleep 3; Write-Host '--- settings.yaml training block ---'; Select-String -Path (Join-Path \$env:APPDATA 'dsh-desktop\harness\settings.yaml') -Pattern 'training','agent-default-model','X-DashScope-DataInspection' -SimpleMatch | ForEach-Object { \$_.Line }; Write-Host '--- workspace.json ---'; Get-Content (Join-Path \$env:APPDATA 'dsh-desktop\harness\storages\workspace.json') -Raw } else { Write-Host 'DSH Desktop.exe not found' }\"" \
  2>&1 | tee -a "ci/logs/cohort-win-$stamp.log"

note "[cohort/win] powering off VM (hard, discard -- leaves clean-base for next run)"
vmrun stop "$WIN_VMX" hard 2>/dev/null || true

note "=== SUMMARY: cohort/windows  cohort-prep=$([ "$rc" = 0 ] && echo PASS || echo FAIL)  verify=$([ "$vrc" = 0 ] && echo PASS || echo FAIL) ==="
[ "$rc" = 0 ] && [ "$vrc" = 0 ]
