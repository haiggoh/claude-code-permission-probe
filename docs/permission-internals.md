# Why the allowlist cannot reach these prompts

Read from the Claude Code binary (2.1.267, re-checked in 2.1.270) and then
**confirmed by experiment** — the measurements are what this repo asserts, the
code reading only explains them. Minified names differ per build, so treat the
identifiers below as landmarks, not stable API.

## The bailout

The Bash analyzer parses a command into subcommands. When it meets shell syntax it
will not reason about, it returns `{kind: "too-complex", reason, nodeType}` for the
**whole command**. Landmarks: `S1o` in 2.1.270 / `JMo` in 2.1.267 (the sandbox
escape), and a `ke()` fallback that formats the reason.

`Contains simple_expansion` is that fallback echoing a raw tree-sitter node type
from a set covering `command_substitution`, `process_substitution`, `expansion`,
`simple_expansion`, `subshell`, `heredoc_redirect`, `test_command` and more. It
reads like a rule name; it is a parser node type.

## Why prefix rules never match

On the too-complex path only two things are consulted:

1. **deny** rules (still enforced — a bailout never weakens a deny), and
2. an **allow** rule whose `ruleContent` equals the **entire command string,
   verbatim** (`ruleContent === command.trim()`).

No `Bash(cmd:*)` prefix rule is tested, because no subcommand was ever extracted
to test one against. Asserted by `tests/test_findings.sh` with a fixture whose
allowlist covers every verb in the command: still BLOCKED.

## Why there is no "don't ask again" row

The decision carries `suppressAlwaysAllowRule`. The binary's own doc string:

> True when the dialog must not offer the persistent "don't ask again" row for
> this ask: accepting it would write a whole-tool allow rule broader than the
> ask's own verb.

Since no verb was parsed, the only rule the UI could offer is a bare whole-tool
`Bash` allow. Rather than quietly offering allow-everything, it offers nothing.

## The sandbox escape, and its limit

With sandboxing on, a too-complex command can be auto-allowed — the sandbox is
containing it, so static analysis is no longer the only safeguard.
`sandbox.autoAllowBashIfSandboxed` defaults to **true**, so `sandbox.enabled` is
the only key needed.

The hatch declines when, among other conditions, a command contains a heredoc
(`<<`), `${` followed by space/pipe, `${!`, `/proc/*/environ`, or an `ERROR` /
`PARSE_ABORT` parse — and, decisively for the common case, when any **assignment
prefix word** contains one of `"'`$\(){}|;&<>*?[]`. That last condition is why
`VAR=$(cmd) && …` still prompts while the same `$(cmd)` in an argument or a
redirect target does not.

Heredocs are listed as a decline reason, yet a quoted heredoc measures ALLOWED:
it parses cleanly, so it never reaches the hatch at all. A reminder that reading
the guard tells you when the hatch *declines*, not when a prompt *appears*.

## One more trap

If `autoMode.classifyAllShell` is ever true, even a blanket whole-tool `Bash`
allow rule is filtered out and every command goes to the classifier. Check it
before concluding that a broad allow rule will help.
