#!/bin/bash
# probe.sh — decide, by experiment, whether Claude Code prompts for a Bash command.
#
# Usage:
#   probe.sh --settings <file> --command '<cmd that must touch $MARK>' [options]
#   probe.sh --help
#
# Options:
#   --settings <file>   settings.json to run the CLI with (required)
#   --command  '<cmd>'  the Bash command to test; MUST create the file $MARK
#   --label    '<name>' label for the output line (default: the command, truncated)
#   --port     <N>      port for the stub API server (default 8791)
#   --timeout  <secs>   watchdog before the CLI is killed (default 20)
#   --keep              keep the scratch dir and CLI output for inspection
#
# Environment:
#   CLAUDE_BIN          claude executable to test (default: `claude` on PATH)
#   PROBE_STUB          path to stub-api.py (default: alongside this script)
#
# Exit status: 0 if the verdict is ALLOWED, 1 if BLOCKED, 2 on usage error.
#
# The verdict is an OUTCOME, not parsed text: the command must create $MARK, and
# the marker's existence decides it. $MARK lives inside the CLI's cwd (also passed
# via --add-dir) so that a sandbox-confined write cannot masquerade as a block.
set -u

HERE=$(cd -- "$(dirname -- "$0")" && pwd)
STUB=${PROBE_STUB:-"$HERE/stub-api.py"}
CLAUDE=${CLAUDE_BIN:-claude}
PORT=8791; S=""; C=""; L=""; LIMIT=20; KEEP=0

while [ $# -gt 0 ]; do
  case "$1" in
    --settings) S=${2:-}; shift 2;;
    --command)  C=${2:-}; shift 2;;
    --label)    L=${2:-}; shift 2;;
    --port)     PORT=${2:-}; shift 2;;
    --timeout)  LIMIT=${2:-}; shift 2;;
    --keep)     KEEP=1; shift;;
    --help|-h)  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) printf 'probe.sh: unknown flag: %s\n' "$1" >&2; exit 2;;
  esac
done

[ -n "$S" ] || { echo "probe.sh: --settings is required" >&2; exit 2; }
[ -n "$C" ] || { echo "probe.sh: --command is required"  >&2; exit 2; }
case "$S" in /*) ;; *) S="$PWD/$S";; esac          # CLI runs from a scratch cwd
[ -f "$S" ] || { echo "probe.sh: no such settings file: $S" >&2; exit 2; }
[ -f "$STUB" ] || { echo "probe.sh: stub not found: $STUB" >&2; exit 2; }
case "$C" in *'$MARK'*) ;; *) echo "probe.sh: --command must create \$MARK, or the verdict is meaningless" >&2; exit 2;; esac
command -v "$CLAUDE" >/dev/null 2>&1 || { echo "probe.sh: claude not found (set CLAUDE_BIN)" >&2; exit 2; }
[ -z "$L" ] && L=$(printf '%.34s' "$C")

WORK=$(mktemp -d "${TMPDIR:-/tmp}/ccprobe.XXXXXX")
MARK="$WORK/mark"
OUTF="$WORK/cli-output.json"
CMD=${C//\$MARK/$MARK}
TIMEDOUT=0

cleanup() {
  [ -n "${SPID:-}" ] && kill "$SPID" 2>/dev/null
  [ "$KEEP" = 1 ] || rm -rf "$WORK"
}
trap cleanup EXIT

"$STUB" --port "$PORT" --command "$CMD" --log "$WORK/stub.log" & SPID=$!
READY=0
for _ in $(seq 1 30); do
  if curl -s -m 1 "http://127.0.0.1:$PORT/v1/models" -o /dev/null; then READY=1; break; fi
  sleep 0.2
done
[ "$READY" = 1 ] || { echo "probe.sh: stub never became ready on port $PORT" >&2; exit 2; }

cd "$WORK" || exit 2
# A BLOCKED command in -p mode waits forever for a prompt no TTY will answer,
# so the run is bounded rather than allowed to hang.
env ANTHROPIC_BASE_URL="http://127.0.0.1:$PORT" \
    ANTHROPIC_AUTH_TOKEN=stub \
    ANTHROPIC_MODEL=claude-opus-5 \
    "$CLAUDE" -p 'go' --settings "$S" --permission-mode acceptEdits \
      --add-dir "$WORK" --strict-mcp-config --output-format json >"$OUTF" 2>&1 &
CPID=$!
WAITED=0
while kill -0 "$CPID" 2>/dev/null; do
  if [ "$WAITED" -ge "$LIMIT" ]; then kill -9 "$CPID" 2>/dev/null; TIMEDOUT=1; break; fi
  sleep 1; WAITED=$((WAITED+1))
done
wait "$CPID" 2>/dev/null

REASON=$(python3 - "$OUTF" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit
for r in (d.get("permission_denials") or []):
    print(r.get("message") or r.get("reason") or r)
    break
# the tool_result carries the analyzer's reason for a too-complex bailout
PY
)

if [ -e "$MARK" ]; then V=ALLOWED; RC=0; else V=BLOCKED; RC=1; fi
printf '%-36s %s' "$L" "$V"
[ "$TIMEDOUT" = 1 ] && printf ' (cli killed at %ss)' "$LIMIT"
[ -n "$REASON" ] && printf '\n%*s<- %s' 37 '' "$REASON"
printf '\n'
[ "$KEEP" = 1 ] && printf '%*skept: %s\n' 37 '' "$WORK"
exit $RC
