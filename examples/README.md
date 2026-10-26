# General-purpose command runner

[`run_command.sh`](run_command.sh) demonstrates using logshuru around one command.
It is a small integration example, not an installed logger subcommand. It uses
the checkout's `../logshuru.sh`; keep that layout when running or copying it.
Requirements are the logger's Bash 4.2+ and GNU-compatible `date`.

From the repository root:

```bash
bash examples/run_command.sh -- printf '%s\n' 'application data'
bash examples/run_command.sh -- bash -c 'printf "tool diagnostic\n" >&2; exit 23'
```

The second invocation returns `23`. You can invoke the example from another
working directory using its absolute path. The command retains that working
directory and inherits stdin and the normal environment.

## Streams and configuration

Logger records default to stderr, keeping command stdout available as data:

```bash
bash examples/run_command.sh -- printf '%s\n' 'application data' > result.txt
LOG_LEVEL=DEBUG bash examples/run_command.sh -- printf '%s\n' 'debug run'
LOGSHURU_FORMAT=json bash examples/run_command.sh -- printf '%s\n' 'JSON run'
```

Normal [logshuru settings](../docs/CONFIGURATION.md) apply. A nonempty
`LOGSHURU_OUTPUT` explicitly overrides the example's stderr default;
`stdout`/`split` can mix logger records with data.
The default is scoped to the runner's logger initialization: it is not introduced
into the command's environment. Caller-exported settings reach the command
unchanged, including an empty value. An empty value selects stderr for the
runner, but retains its usual library-default meaning in a child using logshuru.
Colors retain the logger's `auto` default. Command stdout/stderr are inherited
directly, with no prefixing, capture, or logging pipeline. Consequently, stderr
can contain both lifecycle records and tool diagnostics. JSON mode formats only
logger records; it does not turn arbitrary tool stderr into a JSON Lines stream.

## Execution and status policy

- Require the `--` separator and at least one command argument; misuse exits `2`.
- Forward arguments using `"$@"`, without eval or shell-string reconstruction.
  Lifecycle records omit the executable and arguments to avoid disclosing values
  such as credentials. The command itself can still print its own arguments.
- Run the command in a subshell, isolating builtins that change shell state.
  Use `bash -c '...'` explicitly for pipelines, redirects, or shell syntax.
- Log DEBUG initialization, INFO start, then SUCCESS or ERROR completion with
  command status and elapsed whole seconds using Bash 4.2-compatible `SECONDS`.
- Failed logger initialization stops execution before the command runs.
- Once initialized, lifecycle logging is best-effort: logging failures do not
  prevent command execution or replace its status. A successful command still
  exits `0` if a lifecycle log write fails. A missing executable normally yields
  Bash status `127`; a non-executable command yields `126`.

**Cancellation limitation:** killing only the runner may leave its command
running, and abrupt termination may prevent a completion record. The runner does
not forward signals or manage a process tree. Use the surrounding job runner or
supervisor to manage cancellation of the entire process group. Best-effort logging
does not guarantee cleanup or completion records when interrupted.

The application chooses this policy; the logger itself still reports write
failures. See the [usage guide](../docs/USAGE.md#strict-mode-and-exit-statuses) for
library status semantics and [design decisions](../docs/DESIGN.md) for rationale.

The example introduces no retry, batching, output-file management, or background
process supervision. Domain-specific scripts and workflow integration belong in
the projects using the logger. Run it as a script rather than sourcing it.
