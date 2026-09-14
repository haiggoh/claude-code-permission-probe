#!/bin/bash
# Self-check: does the harness itself work, and can it REPORT FAILURE?
#
# A probe harness that can only ever say ALLOWED is measuring nothing. These
# cases are cheap, need no network, and must pass before any finding is trusted.
#
# Usage: test_harness_selfcheck.sh [--help]
set -u
HERE=$(cd -- "$(dirname -- "$0")" && pwd); ROOT=$(dirname "$HERE")
[ "${1:-}" = "--help" ] && { sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
[ $# -gt 0 ] && { echo "unexpected argument: $1" >&2; exit 2; }

PROBE="$ROOT/bin/probe.sh"; FIX="$ROOT/fixtures"; PASS=0; FAIL=0
ok()   { printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  FAIL %s -- %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# --- usage guards: must exit non-zero WITHOUT doing the work -----------------
for args in "--bogus" "--settings $FIX/nosb.json" "--settings /nope.json --command touch\ \$MARK"; do
  # shellcheck disable=SC2086
  if "$PROBE" $args >/dev/null 2>&1; then bad "usage guard [$args]" "exited 0"; else ok "usage guard rejects [$args]"; fi
done
if "$PROBE" --help | grep -q 'Usage:'; then ok "--help prints usage"; else bad "--help" "no usage line"; fi
if "$PROBE" --settings "$FIX/nosb.json" --command 'touch /tmp/nomarker' >/dev/null 2>&1; then
  bad "\$MARK guard" "accepted a command that cannot be verified"; else ok "rejects a command without \$MARK"; fi

command -v claude >/dev/null 2>&1 || {
  printf '\n  claude not on PATH -- skipping live cases (usage guards still ran)\n'
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ] || exit 1; exit 0; }

# --- the two controls that make every later verdict meaningful ---------------
# POSITIVE: an allowlisted command must come back ALLOWED.
if "$PROBE" --settings "$FIX/nosb.json" --label 'positive control' --command 'touch $MARK' >/dev/null 2>&1
then ok "positive control: allowlisted command is ALLOWED"
else bad "positive control" "an allowlisted command was BLOCKED -- harness cannot see success"; fi

# NEGATIVE: an explicit ask rule must come back BLOCKED. Without this, an
# always-ALLOWED harness would look perfectly healthy.
if "$PROBE" --settings "$FIX/ask.json" --label 'negative control' --command 'touch $MARK' >/dev/null 2>&1
then bad "negative control" "an ask-rule command was ALLOWED -- harness cannot detect a prompt"
else ok "negative control: ask-rule command is BLOCKED"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
