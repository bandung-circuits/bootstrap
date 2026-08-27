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
ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 \
  "$CI_USER@$CI_HOST" \
  'cd ~/Projects/03.systems/bootstrap && bash ci/run-test.sh' \
  > "$LOG" 2>&1
rc=$?

echo "==> CI exit code: $rc"
grep -E "RESULT|SUMMARY" "$LOG" 2>/dev/null
exit $rc
