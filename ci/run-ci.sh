#!/usr/bin/env bash
# run-ci.sh — the ONE command to run CI. Always the same, committed to the repo.
#
# Usage: bash ci/run-ci.sh
#
# What it does:
#   1. SSHes to yuan (the CI host)
#   2. yuan: git fetch + reset --hard origin/main (fresh files)
#   3. yuan: reverts both VMs to clean-base
#   4. yuan: runs ci/run-test.sh (installs + verifies on Linux + Windows)
#   5. Prints the SUMMARY line
#
# Output goes to /tmp/ci.log (overwrite each run).

set -uo pipefail
cd "$(dirname "$0")/.."

CI_USER="${CI_USER:-yuan}"
CI_HOST="${CI_HOST:-10.0.31.44}"
LOG="/tmp/ci.log"

echo "==> CI starting, log: $LOG"

# Refuse to run if a previous run is still alive on the CI host. Two run-test.sh
# on the same two VMs at once corrupts state (revert-under-install, frozen VMs).
if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$CI_USER@$CI_HOST" \
     'pgrep -f "ci/run-test\.sh" >/dev/null 2>&1'; then
  echo "ERROR: a CI run is already in progress on $CI_HOST — not starting another." >&2
  echo "  if it's stale, kill it first:  ssh $CI_USER@$CI_HOST 'pkill -f ci/run-test.sh'" >&2
  exit 1
fi

ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 \
  "$CI_USER@$CI_HOST" \
  'cd ~/Projects/03.systems/bootstrap && bash ci/run-test.sh' \
  > "$LOG" 2>&1
rc=$?

echo "==> CI exit code: $rc"
grep -E "RESULT|SUMMARY" "$LOG" 2>/dev/null
exit $rc
