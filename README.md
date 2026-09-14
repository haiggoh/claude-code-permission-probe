# claude-code-permission-probe

Decide Claude Code permission questions **by experiment, not by reading source**.

`bin/stub-api.py` impersonates the Anthropic API and returns one canned Bash
`tool_use`; `bin/probe.sh` runs the real `claude` CLI against it and reports
**ALLOWED** or **BLOCKED**. No model, no gateway, no API spend, no network.

```console
$ ./bin/probe.sh --settings fixtures/sb.json \
    --command 'mkdir -p ./e2e && printf "x=1\n" > ./e2e/f.meta && touch $MARK'
mkdir -p ./e2e && printf "x=1\n" > ./e  ALLOWED

$ ./tests/run-all.sh
ALL SUITES PASSED
```

## Why it exists

Claude Code sometimes prompts for a trivial-looking Bash command with a reason
like `Contains simple_expansion` or `Redirect target contains $(cmd) output`, and
offers **no "don't ask again"** option. Growing `permissions.allow` does not help,
and it is genuinely hard to tell why from the outside. This makes the question
empirically answerable in about twenty seconds per case.

## Why the verdict is trustworthy

* **Outcome, not text.** The command under test must create `$MARK`; the marker's
  existence is the verdict. Nothing depends on scraping a message.
* **`$MARK` lives inside the CLI's cwd**, which is also passed via `--add-dir`.
  Without this, a *sandbox-confined write* is indistinguishable from a
  *permission block* — an earlier version of this harness got exactly that wrong.
* **A negative control ships with the suite.** `fixtures/ask.json` must report
  BLOCKED. A harness that can only ever say ALLOWED is measuring nothing, and
  that failure mode looks perfectly healthy from the outside.

## Findings (CLI 2.1.270, macOS)

`sandbox.enabled: true` is the designed escape hatch for commands the analyzer
refuses to parse, and it works — **but not unconditionally.** It declines any
command whose **assignment prefix** contains `$` or `(`:

| Command shape | sandbox OFF | sandbox ON |
|---|---|---|
| `wc -l /etc/hosts` (not allowlisted) | BLOCKED | **ALLOWED** |
| `$(cmd)` in an **argument** | — | **ALLOWED** |
| `$(cmd)` in a **redirect target** | — | **ALLOWED** |
| `VAR=$(cmd) && …` | BLOCKED | **BLOCKED** |
| quoted heredoc | — | ALLOWED |
| generous **prefix** allow rules, no sandbox | BLOCKED | — |

So the blocker is the **assignment prefix**, not the redirect the error names.

**Workarounds, both measured:** drop the `VAR=$(...)` prefix (use a literal path,
or `mkdir -p` a fixed directory), or move the dynamic logic into a wrapper script
and allow that entry point.

**Sandbox mode is not free.** It confines writes to the write-root — a `$HOME`
write ran *without prompting* and was then silently dropped — and restricts
network egress. Verified by running the command and *then* attempting the
restricted operation, since a prompt and a confinement look alike otherwise.

Every row above is asserted by `tests/test_findings.sh`, so a CLI update that
changes the analyzer fails the suite instead of quietly invalidating this table.

## Layout

    bin/probe.sh                   the probe (--help)
    bin/stub-api.py                stub Anthropic API, SSE-capable (--help)
    fixtures/*.json                settings permutations, incl. the controls
    tests/run-all.sh               everything, self-check first
    tests/test_harness_selfcheck.sh  usage guards + both controls
    tests/test_findings.sh         re-measures every documented finding
    docs/permission-internals.md   why the allowlist cannot reach this path

## Requirements

`claude` on `PATH` (or set `CLAUDE_BIN`), `python3`, `curl`, `bash`. macOS or
Linux. The sandbox findings are macOS-specific; `bin/probe.sh` itself is not.

## Traps already paid for

* **`--allowed-tools Bash` is itself a blanket allow rule** and silently makes
  every probe pass. Do not pass it.
* The CLI needs **SSE** (`stream: true`); a plain JSON reply is ignored and the
  turn ends with no tool call at all.
* A blocked command under `-p` waits forever for a prompt no TTY will answer,
  hence the watchdog. `(cli killed at Ns)` is teardown lag, not an invalid verdict.

## License

MIT
