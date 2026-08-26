#!/usr/bin/env bash
# run-test.sh — runs ON the CI Mac host.
# Reverts each VM to clean-base, boots, SSHes in to run the installer + verify,
# then reports PASS/FAIL for Linux and Windows. Fully unattended.
#
# Prereqs: see ci/vm-setup.md. Needs .env (gitignored) at the repo root with
# host addresses, VM paths, and the test API key — copy .env.example to .env.
set -uo pipefail
cd "$(dirname "$0")/.."

REPO_RAW="https://bandung-circuits.github.io/bootstrap"
# fall back to local files if testing pre-publish:
INSTALL_URL="${REPO_RAW}/install.sh"
PS1_URL="${REPO_RAW}/install.ps1"

ENV_FILE=".env"

fail(){ printf '\033[1;31m==>\033[0m %s\n' "$*"; exit 1; }
note(){ printf '\033[1;32m==>\033[0m %s\n' "$*"; }

[ -f "$ENV_FILE" ] || fail "missing $ENV_FILE — copy .env.example to .env and fill in (see ci/vm-setup.md)"
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a

mkdir -p ci/logs
stamp=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "manual")

vmrun(){ command vmrun -T fusion "$@"; }
ssh_wait(){
  local host="$1" user="$2" tries=40
  until ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$user@$host" 'echo ok' 2>/dev/null | grep -q ok; do
    tries=$((tries-1)); [ "$tries" -le 0 ] && return 1; sleep 5
  done
}

# ---------- Linux ----------
test_linux(){
  note "[Linux] revert to clean-base"
  vmrun revertToSnapshot "$LINUX_VMX" clean-base || fail "revert linux failed"
  vmrun start "$LINUX_VMX" nogui 2>/dev/null || vmrun start "$LINUX_VMX"
  note "[Linux] waiting for SSH at $LINUX_HOST"
  ssh_wait "$LINUX_HOST" "$LINUX_USER" || fail "linux SSH timeout"
  note "[Linux] running installer"
  ssh -o StrictHostKeyChecking=no "$LINUX_USER@$LINUX_HOST" \
    "curl -fsSL $INSTALL_URL | bash -s -- --provider=$TEST_PROVIDER --api-key=$TEST_API_KEY" \
    2>&1 | tee "ci/logs/linux-install-$stamp.log"
  note "[Linux] verifying"
  # copy verify script in and run with env
  scp -o StrictHostKeyChecking=no ci/verify/verify-linux.sh "$LINUX_USER@$LINUX_HOST":/tmp/verify.sh
  ssh -o StrictHostKeyChecking=no "$LINUX_USER@$LINUX_HOST" \
    "TEST_PROVIDER=$TEST_PROVIDER TEST_API_KEY=$TEST_API_KEY bash /tmp/verify.sh" \
    2>&1 | tee "ci/logs/linux-verify-$stamp.log"
}

# ---------- Windows ----------
test_windows(){
  note "[Windows] revert to clean-base"
  vmrun revertToSnapshot "$WIN_VMX" clean-base || fail "revert windows failed"
  vmrun start "$WIN_VMX" nogui 2>/dev/null || vmrun start "$WIN_VMX"
  note "[Windows] waiting for SSH at $WIN_HOST"
  ssh_wait "$WIN_HOST" "$WIN_USER" || fail "windows SSH timeout"
  note "[Windows] running installer (PowerShell)"
  ssh -o StrictHostKeyChecking=no "$WIN_USER@$WIN_HOST" \
    "powershell -NoProfile -Command \"irm $PS1_URL | iex; exit \\\$LASTEXITCODE\"" \
    2>&1 | tee "ci/logs/win-install-$stamp.log"
  note "[Windows] verifying"
  scp -o StrictHostKeyChecking=no ci/verify/verify-windows.ps1 "$WIN_USER@$WIN_HOST":verify.ps1
  ssh -o StrictHostKeyChecking=no "$WIN_USER@$WIN_HOST" \
    "powershell -NoProfile -Command \"\$env:TEST_PROVIDER='$TEST_PROVIDER'; \$env:TEST_API_KEY='$TEST_API_KEY'; .\verify.ps1\"" \
    2>&1 | tee "ci/logs/win-verify-$stamp.log"
}

note "=== Bootstrap CI run $stamp ==="
test_linux  ; lr=$?
test_windows; wr=$?
echo
note "=== SUMMARY: Linux=$([ $lr -eq 0 ] && echo PASS || echo FAIL)  Windows=$([ $wr -eq 0 ] && echo PASS || echo FAIL) ==="
[ $lr -eq 0 ] && [ $wr -eq 0 ]
