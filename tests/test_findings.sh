#!/bin/bash
# Re-measure the documented findings against the Claude Code on this machine.
#
# Every row in README.md's shape table is asserted here, so a CLI update that
# changes the permission analyzer shows up as a test failure instead of quietly
# invalidating the docs. Run tests/test_harness_selfcheck.sh FIRST -- if the
# controls there do not pass, nothing below means anything.
#
# Usage: test_findings.sh [--help]
# Needs: claude on PATH (or $CLAUDE_BIN). No network, no model, no API spend.
set -u
HERE=$(cd -- "$(dirname -- "$0")" && pwd); ROOT=$(dirname "$HERE")
[ "${1:-}" = "--help" ] && { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }
[ $# -gt 0 ] && { echo "unexpected argument: $1" >&2; exit 2; }

PROBE="$ROOT/bin/probe.sh"; FIX="$ROOT/fixtures"; PASS=0; FAIL=0
command -v "${CLAUDE_BIN:-claude}" >/dev/null 2>&1 || { echo "claude not found; set CLAUDE_BIN" >&2; exit 2; }
printf 'claude %s\n\n' "$("${CLAUDE_BIN:-claude}" --version 2>/dev/null)"

# expect <ALLOWED|BLOCKED> <settings> <label> <command>
expect() {
  local want=$1 set=$2 label=$3 cmd=$4 got
  if "$PROBE" --settings "$FIX/$set" --label "$label" --command "$cmd" >/dev/null 2>&1
  then got=ALLOWED; else got=BLOCKED; fi
  if [ "$got" = "$want" ]; then printf '  ok   %-42s %s\n' "$label" "$got"; PASS=$((PASS+1))
  else printf '  FAIL %-42s want %s, got %s\n' "$label" "$want" "$got"; FAIL=$((FAIL+1)); fi
}

# --- the sandbox escape hatch is real, and it is NOT unconditional -----------
expect BLOCKED sboff.json 'unallowlisted cmd, sandbox OFF'   'wc -l /etc/hosts >/dev/null && touch $MARK'
expect ALLOWED sb.json    'unallowlisted cmd, sandbox ON'    'wc -l /etc/hosts >/dev/null && touch $MARK'

# --- shape map: the blocker is the ASSIGNMENT PREFIX, not the redirect -------
expect ALLOWED sb.json 'cmdsub in an ARGUMENT'          'wc -l "$(echo /etc/hosts)" >/dev/null && touch $MARK'
expect ALLOWED sb.json 'cmdsub in a REDIRECT TARGET'    'printf "x\n" > "$(echo .)/r.meta" && touch $MARK'
expect BLOCKED sb.json 'cmdsub in an ASSIGNMENT prefix' 'D=$(echo .) && wc -l /etc/hosts >/dev/null && touch $MARK'
expect ALLOWED sb.json 'quoted heredoc'                 'cat > hd.txt <<'"'"'EOF'"'"'
literal $notexpanded
EOF
touch $MARK'

# --- the user-reported command, and the two verified workarounds -------------
RPT='CFGD=$(mktemp -d) && printf "x=1\n" > "$CFGD/f.meta" && ls "$CFGD" && touch $MARK'
expect BLOCKED sboff.json 'reported cmd, sandbox OFF' "$RPT"
expect BLOCKED sb.json    'reported cmd, sandbox ON'  "$RPT"
expect ALLOWED sb.json    'workaround: literal path'  'mkdir -p ./e2e && printf "x=1\n" > ./e2e/f.meta && ls ./e2e && touch $MARK'

# --- an allow rule matching the WHOLE command verbatim is the only rule that
# --- reaches the too-complex path; a prefix rule provably does not.
expect BLOCKED prefixrule.json 'prefix allow rule does NOT reach it' "$RPT"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
