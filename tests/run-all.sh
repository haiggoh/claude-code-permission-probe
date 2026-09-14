#!/bin/bash
# Run every test in this repo, self-check first.
# Usage: run-all.sh [--help]
set -u
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
[ "${1:-}" = "--help" ] && { sed -n '2,3p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
[ $# -gt 0 ] && { echo "unexpected argument: $1" >&2; exit 2; }
RC=0
echo "== harness self-check =="; "$HERE/test_harness_selfcheck.sh" || RC=1
echo; echo "== documented findings =="; "$HERE/test_findings.sh" || RC=1
echo; [ $RC -eq 0 ] && echo "ALL SUITES PASSED" || echo "SOME SUITES FAILED"
exit $RC
