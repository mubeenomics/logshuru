# Configuration and output reference

[Quick start](../README.md) · [Usage](USAGE.md) · [Installation](INSTALLATION.md)

## Settings

| Setting | Default | Accepted values / purpose |
| --- | --- | --- |
| `LOG_LEVEL` | `PROCESS` | Minimum severity: TRACE through CRITICAL |
| `LOGSHURU_COLOR` | `auto` | `auto`, `always`, `never` |
| `LOGSHURU_OUTPUT` | `stdout` | `stdout`, `stderr`, `split` |
| `LOGSHURU_FORMAT` | `text` | `text`, `json` |
| `LOGSHURU_TIMESTAMP_FORMAT` | `%F %T.%3N` | GNU-date format |
| `LOGSHURU_TZ` | Inherited TZ/local time | `UTC` or installed IANA zone |
| `LOGSHURU_FILE` | Disabled | Duplicate append destination |

## Initialization

Set environment configuration before starting the CLI or sourcing the library.
Unset/empty values select defaults. Level/enum names are case-insensitive;
whitespace is not trimmed (` ERROR ` is invalid). Invalid nonempty levels/enums
fail initialization with status `1` and a plain stderr diagnostic. A failed source
returns to its caller rather than explicitly exiting it; handle that failure
before calling library functions. Initialization does not promise transactional
restoration of previously initialized state.

Settings are captured at initialization. Later environment assignments do not
reconfigure active settings; use `set_log_level` for runtime level changes.
Exported settings reach children when they source the library themselves.
`LOG_LEVEL` remains the established level setting; other settings use `LOGSHURU_*`.

Some ambient state is intentionally checked at emission time: terminal status,
`NO_COLOR`, `TERM`, and inherited TZ/system timezone without an explicit override.

```bash
LOG_LEVEL=WARNING logshuru ERROR "Visible event"
export LOGSHURU_OUTPUT=stderr LOGSHURU_FORMAT=json
source "$HOME/.local/bin/logshuru" || exit 1
log INFO "Configured library event"
```

## Colors

| Mode | Behavior |
| --- | --- |
| `auto` | Colors only when destination is a terminal, NO_COLOR is unset/empty, and TERM is not dumb |
| `always` | Colors even on redirected output, overriding NO_COLOR and TERM=dumb |
| `never` | No logger-generated colors |

```bash
LOGSHURU_COLOR=never logshuru INFO "Plain text"
LOGSHURU_COLOR=always logshuru INFO "Retain colors" > colored.log
NO_COLOR=1 logshuru INFO "Plain text in automatic mode"
```

Any nonempty NO_COLOR value, including `0`, disables automatic colors; an empty
value does not. Actual destination status is checked per call, including
redirection. The policy also applies to help and colored invalid-call diagnostics
on their respective descriptors. Startup diagnostics are plain text.

Colors affect logger formatting, not escape sequences inside user text. JSON
records and file copies never receive logger colors. Redirected output used to
always contain colors; `LOGSHURU_COLOR=always` restores that behavior.

## Output streams

| Mode | Log destination |
| --- | --- |
| `stdout` | All levels to stdout |
| `stderr` | All levels to stderr |
| `split` | WARNING/ERROR/CRITICAL to stderr; lower levels to stdout |

```bash
LOGSHURU_OUTPUT=stderr logshuru INFO "Processing item"
LOGSHURU_OUTPUT=split logshuru WARNING "Check item"
```

Only records are routed. Usage/configuration/invalid-call diagnostics always use
stderr. Help/version/getter output always uses stdout. Setter INFO notifications
are records and follow normal routing/filtering.

Automatic colors follow the selected descriptor's actual terminal status.
Writing to stderr is not itself a failure. Failed stream writes return nonzero;
filtered events write neither stream and succeed even with closed descriptors.

## Timestamps

`LOGSHURU_TIMESTAMP_FORMAT` defaults to `%F %T.%3N`. Unset/empty selects that
format. Custom text is passed as one literal argument to GNU date, not evaluated
as shell code or a printf format. GNU date interprets individual directives;
logshuru does not independently validate them. No case conversion or whitespace
trimming is applied. Timestamp rendering is literal, except command substitution
strips trailing newlines from date output.

```bash
LOGSHURU_TZ=UTC LOGSHURU_TIMESTAMP_FORMAT='%Y-%m-%dT%H:%M:%SZ' \
    logshuru INFO "UTC event"
LOGSHURU_TZ=Asia/Kolkata LOGSHURU_TIMESTAMP_FORMAT='%F %T.%3N %z' \
    logshuru INFO "Local event"
```

Unset/empty `LOGSHURU_TZ` retains inherited TZ/system local-time behavior. Explicit
overrides accept case-sensitive installed IANA names or `UTC`; arbitrary POSIX
timezone expressions and absolute zone-file paths are not accepted here.
Existing POSIX TZ values still work without a LOGSHURU_TZ override.

Invalid explicit zones fail initialization with status `1`; they do not silently
fall back to UTC. Named zones are checked under captured TZDIR (default
`/usr/share/zoneinfo`). UTC needs no zone database. Overrides apply only to date
and never change caller TZ/TZDIR. Explicit format/zone/TZDIR choices are captured
when initialized.

Each emitted event invokes date once. Failure returns nonzero with stderr
diagnostics and emits neither stream nor file record. Filtered events skip date.
Colors, routing, and source context work with custom timestamps.

## File logging

`LOGSHURU_FILE` duplicates emitted events to an append destination; unset/empty
disables it. It does not replace the selected stream or change routing.

```bash
LOGSHURU_FILE="$PWD/run.log" LOGSHURU_OUTPUT=stderr \
    logshuru INFO "Starting command"
```

For library use, export the setting before sourcing. The path is captured then;
relative paths are anchored to that directory, so later cd calls do not redirect
the parent shell's logs. Export an absolute path for children that should share
one file from different working directories. Paths are literal, including spaces
and shell metacharacters.

Copies reuse the stream timestamp, padded text level, source context, message,
and trailing record newline. They omit logger-generated colors even in `always`
mode. User-supplied escapes/newlines are preserved by the selected format. JSON
copies contain the exact same object as the stream.

The file opens in append mode per emitted event, creates missing files with caller
umask, and preserves existing contents. Parent directories must exist. Existing
destinations must be regular files; directories, FIFOs, and devices are rejected.
Sourcing, help/version/getter output, invalid calls, and filtered events do not
open/create the file.

Stream output is attempted first, then file append independently. Logging returns
`1` if either fails. File errors are diagnosed on stderr when writable. Failed
append does not roll back stream output or partial file bytes. Timestamp failure
emits neither copy. Setter notification failure leaves the valid level change
applied while returning nonzero.

There is no rotation, retention, or interprocess locking. Use external rotation
when needed; use shell redirection to suppress the stream when only a file copy
is desired.

## JSON Lines

Set `LOGSHURU_FORMAT=json` before starting/sourcing. Text remains the default.
JSON emits one UTF-8 object followed by a newline per event:

```bash
LOGSHURU_FORMAT=json LOGSHURU_TZ=UTC \
    LOGSHURU_TIMESTAMP_FORMAT='%Y-%m-%dT%H:%M:%S.%3NZ' \
    logshuru INFO "Operation completed"
```

```json
{"timestamp":"2026-10-25T10:30:00.123Z","level":"INFO","file":"cli","function":"cli","line":0,"message":"Operation completed"}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `timestamp` | string | Timestamp using configured format/timezone |
| `level` | string | Uppercase, unpadded level |
| `file` | string | Caller basename, cli, or unknown |
| `function` | string | Immediate caller, main at top level, or cli |
| `line` | number | One-based call line; 0 means unavailable |
| `message` | string | Original message, fragments joined as in text mode |

See [source context](USAGE.md#source-context) for invocation details. JSON does
not change timestamp defaults: the example explicitly chooses UTC and an
ISO-style format. Without those settings, inherited TZ/local time and `%F %T.%3N`
still apply. Logger colors are suppressed even with LOGSHURU_COLOR=always.

Serialization is pure Bash with no extra runtime dependency. Quotes, backslashes,
and ASCII control characters are escaped. Multiline messages remain one physical
line and decode to their original text. Valid UTF-8 is preserved, including user
escape characters encoded as JSON escapes. Malformed UTF-8 in any string field
returns `1`, diagnoses on stderr, and emits neither copy. Bash strings and command
arguments cannot contain embedded NUL bytes.

Byte-wise validation/escaping costs more CPU for long strings than text output.
logshuru is intended for normal log lines rather than high-volume serialization.
Both formats invoke GNU date once per emitted event; filename extraction launches
no basename process.

Routing, filtering, context, strict-mode behavior, and independent destination
failures are unchanged. File output receives identical JSON records. Help,
version/getter, and human diagnostics retain their interfaces; log files contain
records, not diagnostics.

For library use and optional parsing:

```bash
export LOGSHURU_FORMAT=json LOGSHURU_TZ=UTC
export LOGSHURU_FILE="$PWD/run.jsonl"
source "$HOME/.local/bin/logshuru" || exit 1
log INFO "Starting command"
jq -c 'select(.level == "ERROR")' run.jsonl
```

jq is a consumer/test tool, not a requirement for emitting JSON. Text preserves
newlines/terminal escapes and can imitate records; choose JSON for framing
untrusted input. Tool diagnostics mixed into stderr do not become JSON just
because logger records use JSON.
