# Usage guide

[Quick start](../README.md) · [Installation](INSTALLATION.md) · [Configuration](CONFIGURATION.md)

Examples assume the installed script is named `logshuru` on PATH. To use a
checkout directly, invoke `bash ./logshuru.sh` or source its absolute path.

## CLI

```bash
logshuru INFO "Application started"
logshuru ERROR "Connection failed"
logshuru SUCCESS "Operation completed"
logshuru --help
logshuru --version
```

Logging requires a level and at least one message argument. Missing arguments
return `1` with usage information on stderr, including under `set -u`. An empty
message (`logshuru INFO ""`) is valid; a missing message is invalid even when
its level would be filtered.

## Library functions

The public functions are `log`, `set_log_level`, and `get_log_level`. Source before
calling them, and handle initialization failure:

```bash
source "$HOME/.local/bin/logshuru" || exit 1
log INFO "Starting processing"
set_log_level DEBUG
log DEBUG "Processing an item"
printf 'Current level: %s\n' "$(get_log_level)"
```

`_logshuru_*` helpers/state are reserved private names. Generic caller names such
as `VERSION`, `COLORS`, and `main` are preserved. Sourcing is silent on success
and also works inside a loader function; state remains available after it returns:

```bash
load_logger() { source "$HOME/.local/bin/logshuru"; }
load_logger || exit 1
log INFO "Logger ready"
```

### Changing levels

Severity increases in this order:

| Level | Color | Purpose |
| --- | --- | --- |
| TRACE | Bold cyan | Detailed tracing |
| DEBUG | Bold blue | Debugging |
| PROCESS | Bold purple | Processing stages (default threshold) |
| INFO | Bold white | General information |
| SUCCESS | Bold green | Successful operations |
| WARNING | Bold yellow | Warning conditions |
| ERROR | Bold red | Errors |
| CRITICAL | Bold text on red | Critical conditions |

Set `LOG_LEVEL` before starting the CLI or sourcing. Changing it after sourcing
does not update active filtering; use `set_log_level` instead.

The setter requires exactly one nonempty level, normalizes it to uppercase,
updates the active threshold, and exports `LOG_LEVEL`. Invalid, empty, missing,
or extra arguments return `1` with stderr diagnostics and leave both settings
unchanged. Its INFO notification follows the new threshold and configured routing.
If that notification fails, the setter returns nonzero but the new level remains
active/exported. A filtered notification succeeds. The notification's context
identifies the application's setter call.

`get_log_level` prints the uppercase active level on stdout. See
[configuration initialization](CONFIGURATION.md#initialization) for environment
defaults and normalization.

## Strict mode and exit statuses

logshuru supports `set -euo pipefail` and preserves caller shell options:

```bash
#!/bin/bash
set -euo pipefail
source "$HOME/.local/bin/logshuru"
set_log_level WARNING
log INFO "Filtered without interrupting this script"
log ERROR "An event; severity alone does not terminate the script"
```

| Operation | Status |
| --- | --- |
| Successfully emitted or filtered event, including ERROR/CRITICAL | `0` |
| Invalid call or initialization | Nonzero |
| Timestamp, serialization, or destination write failure | Nonzero |
| Help, version, or getter write failure | Nonzero |

Unhandled failures can terminate scripts under `set -e`. Use `if` or `||` when
recovery is intended. Filtered calls need no writable output and do not generate
timestamps or open files. With pipefail, a successful log call at a pipeline's
end does not hide an earlier command's failure.

The application decides how logging status relates to its own operation. For
example, preserve a failed tool's exit code even if error logging fails:

```bash
if some_command; then
    log SUCCESS "Command completed"
else
    status=$?
    log ERROR "Command failed exit=$status" || :
    exit "$status"
fi
```

## Messages and text output

Extra message arguments are joined with spaces independently of caller IFS:
`log INFO first 'second part' third` logs `first second part third`. The caller's
IFS is preserved. Percent signs and backslash sequences are rendered literally.
Actual tabs/newlines already in the message are preserved:

```bash
log INFO 'Literal backslash-n: \n'
log INFO $'First line\nSecond line'
```

A text record includes timestamp, padded level, and source context:

```text
2026-10-25 14:32:45.123 | INFO     | script.sh:main:42 - Your message here
```

**Untrusted messages:** preserved newlines/terminal escapes can imitate additional
records or formatting. Use [JSON mode](CONFIGURATION.md#json-lines) for single-line
framing of untrusted messages or metadata, including source filenames/timestamps.

### Source context

| Invocation | Context |
| --- | --- |
| Sourced `log` call | Caller basename, immediate caller function, and one-based call line |
| Top-level call | Caller basename, `main`, and call line |
| Setter INFO notification | Application file/function/line calling `set_log_level` |
| Standalone CLI | `cli:cli:0`; invoking shell source location is unavailable |
| Sourced `bash -c` command string | `unknown` without a source filename; available function/line information |

A wrapper's log call reports the wrapper, not its outer caller. Functions from
other sourced files report their defining file. Line `0` means unavailable;
older supported Bash versions can report it in command strings.

## Child shells

Each new Bash process must source logshuru. Functions are not automatically
exported because their helpers and arrays must be initialized together:

```bash
logger_path="$HOME/.local/bin/logshuru"
source "$logger_path" || exit 1
set_log_level ERROR
bash -c 'source "$1" || exit; log ERROR "Child message"' bash "$logger_path"
```

The child inherits exported `LOG_LEVEL`, including setter changes, when sourcing.
Changes in the child do not alter the parent. Parenthesized subshells, such as
`(log INFO "Subshell message")`, retain initialized state and need not source again.

## Recipes

### Keep command-substitution data separate

```bash
export LOGSHURU_OUTPUT=stderr
source "$HOME/.local/bin/logshuru" || exit 1
item_id=$(log INFO "Reading item ID"; printf '%s' 'item-42')
```

### Development and production levels

```bash
if [[ "${ENVIRONMENT:-development}" == production ]]; then
    set_log_level WARNING
else
    set_log_level DEBUG
fi
log DEBUG "Detailed diagnostics"
log INFO "Application initialized"
```

### Log progress in a loop

```bash
set_log_level DEBUG
for i in {1..3}; do
    log DEBUG "Processing item $i"
    if [[ "$i" -eq 2 ]]; then log WARNING "Check this item"; fi
done
log SUCCESS "Processing completed"
```

### Run a command with lifecycle logs

The checkout's [command-runner example](../examples/README.md) forwards arguments
directly and logs start, completion/failure, and elapsed seconds. Lifecycle logs
default to stderr; after initialization, they are best-effort and the command's
status is preserved. Arguments are omitted from records. Killing only the runner
may leave the command running; see the example's
[cancellation limitation](../examples/README.md#execution-and-status-policy).

```bash
bash examples/run_command.sh -- printf '%s\n' 'application data'
```
