# logshuru

logshuru is a logging utility for Bash, inspired by Python’s [loguru](https://github.com/Delgan/loguru).
It provides structured and color-coded log messages with contextual details like timestamps, source file, and line number.
You can use it as a standalone CLI tool or source it as a library in your scripts, making it ideal for both small shell scripts and production pipelines.
With 8 configurable log levels, level filtering, and a lightweight Bash-based runtime, logshuru helps bring clarity and consistency to your Bash logging.

## Table of Contents

- [Features](#features)
- [Installation](#installation)
  - [Requirements](#requirements)
  - [Quick Install](#quick-install)
- [Usage](#usage)
  - [As a CLI Tool](#as-a-cli-tool)
  - [As a Library](#as-a-library)
  - [Using Strict Mode](#using-strict-mode)
- [Output Format](#output-format)
- [Log Levels](#log-levels)
  - [Using Environment Variable](#using-environment-variable)
  - [Using set\_log\_level Function](#using-set_log_level-function)
  - [Get Current Log Level](#get-current-log-level)
- [Examples](#examples)
  - [Basic Script with Logging](#basic-script-with-logging)
  - [Error Handling](#error-handling)
  - [Production vs Development](#production-vs-development)
- [Configuration](#configuration)
  - [Default Log Level](#default-log-level)
  - [Colors](#colors)
  - [Output Streams](#output-streams)
- [Contributing](#contributing)
  - [Running Tests](#running-tests)
  - [Static Analysis](#static-analysis)
  - [Formatting](#formatting)
  - [Running All Checks](#running-all-checks)
  - [Continuous Integration](#continuous-integration)
- [Acknowledgments](#acknowledgments)

## Features

- **Colored Output** - Beautiful, color-coded log levels for easy visual parsing
- **Contextual Information** - Automatic inclusion of timestamp, file, function, and line number
- **8 Log Levels** - From TRACE to CRITICAL for granular control
- **Level Filtering** - Control what gets logged with configurable minimum log levels
- **Dual Mode** - Use as a CLI tool or source as a library in your scripts
- **Lightweight Runtime** - Bash plus `date` and `basename`; no language package installation required

## Installation

### Requirements

- **Bash 4.0 or later:** the implementation uses associative arrays and case
  conversion introduced in Bash 4. Run it with Bash or source it from Bash;
  POSIX `sh`, Dash, and Zsh are not supported interpreters.
- **GNU-compatible `date` on `PATH`:** timestamp generation uses
  `date +"%F %T.%3N"`. The command must support `%F`, `%T`, and `%3N` for
  millisecond formatting. GNU coreutils provides a suitable `date`.
- **`basename` on `PATH`:** used for source filenames and CLI help/usage text.
  GNU coreutils provides this command too.

ANSI-compatible terminals display the colors. A terminal is not required to run
the logger. The default color mode, `auto`, omits logger-generated ANSI sequences
when output is redirected to a file or pipe. Set `LOGSHURU_COLOR=always` to
retain colors in redirected output, or `never` to disable them everywhere.

#### Platform compatibility

The initial CI target is **Ubuntu 22.04 on x86_64**, using its system Bash 5.1
and GNU coreutils. Local verification used Linux with Bash 5.1.16 and GNU
coreutils 8.32. Bash 4.0 is the implementation's minimum language requirement;
older Bash versions and other platforms are not covered by the current CI job.

The default Bash 3.2 and BSD `date` shipped with macOS do not meet these
requirements. To use logshuru there, provide a newer Bash and a GNU-compatible
command named `date` on `PATH`. Installing a command named only `gdate` does not
change the logger's `date` invocation. The script's shebang is `#!/bin/bash`;
if a suitable Bash is installed elsewhere, invoke that Bash explicitly or source
the library from a script already running under it.

To inspect your environment:

```bash
bash --version
command -v date basename
date +"%F %T.%3N"
```

The last command should produce `YYYY-MM-DD HH:MM:SS.mmm`, with three numeric
fractional-second digits. Timestamps use local time, honoring `TZ` when set.

#### Installation and development tools

The quick-install instructions below additionally use `curl`, `chmod`, `sudo`,
and `mv`. These are installation tools, not logging dependencies. The regression
suite requires Bats-core 1.5.0 or later; see [Running Tests](#running-tests).

### Quick Install

```bash
# Download the script
curl -O https://raw.githubusercontent.com/mubeenomics/logshuru/main/logshuru.sh

# Make it executable
chmod +x logshuru.sh

# Move to your PATH for system-wide access
sudo mv logshuru.sh /usr/local/bin/logshuru
```

## Usage

### As a CLI Tool

```bash
# Basic usage
logshuru INFO "Application started"
logshuru ERROR "Failed to connect to database"
logshuru SUCCESS "Operation completed successfully"

# View help
logshuru --help

# Check version
logshuru --version
```

### As a Library

Source the script in your Bash scripts to use the logging functions:

```bash
#!/bin/bash

# Source logshuru
source logshuru

# Use the log function
log INFO "Starting processing..."
log DEBUG "Processing item: $item"
log SUCCESS "Processing completed"
log ERROR "Something went wrong!"
```

Each new Bash process, such as one started with `bash -c` or by running another
script, must source logshuru itself. Logging functions are not automatically
exported: they depend on helper functions and associative arrays that need to be
initialized together.

```bash
# Replace this with the absolute path to your copy of the library.
logger_path="/absolute/path/to/logshuru.sh"
source "$logger_path"
set_log_level ERROR

# Pass the path as an argument, keeping it safe even if it contains spaces.
bash -c 'source "$1"; log ERROR "Message from child Bash"' bash "$logger_path"
```

The child inherits an exported `LOG_LEVEL`, including values set through
`set_log_level`, when it initializes the library. Later changes in the child do
not change the parent's level. Parenthesized subshells, such as
`(log INFO "Subshell message")`, retain the initialized functions and state and
do not need to source the library again.

### Using Strict Mode

logshuru supports `set -euo pipefail` and preserves the caller's shell options:

```bash
#!/bin/bash
set -euo pipefail

source logshuru
set_log_level WARNING
log INFO "Filtered without interrupting the script"
log ERROR "An error event; logging it does not terminate the script"
```

Valid emitted and filtered messages return `0`. Invalid calls, failed
initialization, and output failures return nonzero and can terminate a script
under `set -e`. Handle expected failures explicitly using `if` or `||` when the
script should recover. With `pipefail` enabled, a successful logging call at the
end of a pipeline does not hide an earlier command's failure.

## Output Format

Both CLI logging and `log` require a level and at least one message argument.
A missing message is an error, even when the level would be filtered. An
explicitly empty message (`log INFO ""`) is valid. Additional message arguments
are joined with spaces, so `log INFO first second` logs `first second`.
Missing arguments return `1` with usage information on stderr, including when
Bash nounset mode (`set -u`) is enabled.

Each log entry includes:

```text
2025-10-01 14:32:45.123 | INFO | script.sh:main:42 - Your message here
└──────────┬──────────┘  └──┬─┘  └───────┬───────┘  └────────┬────────┘
       Timestamp          Level   Source Location         Message
```

Messages are rendered literally: backslash sequences such as `\n`, `\t`, and
`\c` are not interpreted, and percent signs are not treated as format directives.
Actual tabs and newlines already present in a message are preserved. To include
a newline deliberately, use Bash's ANSI-C quoting:

```bash
log INFO 'Literal backslash-n: \n'
log INFO $'First line\nSecond line'
```

Source context depends on how logshuru is called:

| Invocation | Source context |
| ---------- | -------------- |
| Sourced library in a script | Caller file basename, immediate caller function, and the one-based line containing the `log` call |
| Top-level call in a script | Caller file basename, `main`, and the call line |
| Standalone CLI | `cli:cli:0`, indicating that the invoking shell's source location is unavailable |
| Sourced library in a command string such as `bash -c` | `unknown` when no source filename is available; function and line use the context Bash provides |

For example, `logshuru INFO "Started"` reports `cli:cli:0`. Source the library
and call `log INFO "Started"` from a script to obtain that script's location.
If a wrapper function calls `log`, the location identifies the call inside the
wrapper. Functions defined in other sourced files report their defining file.
Line `0` is an unavailable-location marker, not a real source line.

## Log Levels

logshuru supports 8 log levels (in ascending order of severity):

| Level        | Color          | Description                  |
| ------------ | -------------- | ---------------------------- |
| **TRACE**    | Cyan (Bold)    | Detailed tracing information |
| **DEBUG**    | Blue (Bold)    | Debugging messages           |
| **PROCESS**  | Purple (Bold)  | Process-level messages       |
| **INFO**     | White (Bold)   | General information          |
| **SUCCESS**  | Green (Bold)   | Successful operations        |
| **WARNING**  | Yellow (Bold)  | Warning conditions           |
| **ERROR**    | Red (Bold)     | Error messages               |
| **CRITICAL** | Red Background | Critical conditions          |

### Using Environment Variable

`LOG_LEVEL` is read when the CLI starts or the library is sourced. Values are
case-insensitive: `error`, `ERROR`, and `ErRoR` select the same threshold, and
`get_log_level` reports the uppercase name. Unset or empty values use `PROCESS`.
Whitespace is not trimmed; values such as ` ERROR ` are invalid.

```bash
# Only show WARNING and above (WARNING, ERROR, CRITICAL)
export LOG_LEVEL="WARNING"

logshuru INFO "This won't be shown"
logshuru ERROR "This will be shown"
```

Invalid nonempty values produce a diagnostic on stderr and fail initialization
with status `1`, rather than silently selecting a different threshold. When
sourced, the library returns the failure to the caller; handle it before using
the logging functions:

```bash
source logshuru || exit 1
```

After sourcing, changing `LOG_LEVEL` alone does not update the active threshold.
Use `set_log_level` to change it in the current shell.

### Using set_log_level Function

The setter requires exactly one nonempty level argument. It accepts
case-insensitive level names, updates the active threshold,
and exports the uppercase `LOG_LEVEL` for child processes. Invalid or empty
values return `1` with a diagnostic and leave the active and exported settings
unchanged. Missing or extra arguments also return `1` with usage information
without changing either setting.

After a valid level change, the setter logs an INFO notification. If writing that
notification fails, the setter returns nonzero, but the new level remains active
and exported. A notification suppressed by filtering still returns `0`.

```bash
#!/bin/bash

# Source logshuru
source logshuru

# Set minimum log level to DEBUG
set_log_level "DEBUG"

# Use the log function
log TRACE "This won't be shown"
log DEBUG "This will be shown"
log INFO "This will also be shown"
```

### Get Current Log Level

```bash
#!/bin/bash

# Source logshuru
source logshuru

# Get current log level
current_level=$(get_log_level)
echo "Current log level: $current_level"
```

## Examples

### Basic Script with Logging

```bash
#!/bin/bash

# Source logshuru
source logshuru

log INFO "Script started"

# Set log level
set_log_level "DEBUG"

# Loop with logging and conditional warning
for i in {1..3}; do
    log DEBUG "Processing iteration $i"
        if [ $i -eq 2 ]; then
            log WARNING "Halfway through processing"
        fi
done

log SUCCESS "Script completed successfully"
```

### Error Handling

```bash
#!/bin/bash

# Source logshuru
source logshuru

# Define a function with logging and error handling
perform_operation() {
    log PROCESS "Starting critical operation"

    if ! command_that_might_fail; then
        log ERROR "Operation failed"
        return 1
    fi

    log SUCCESS "Operation succeeded"
    return 0
}

# Run the function with loggin and exit on failure
if ! perform_operation; then
    log CRITICAL "Fatal error occurred, exiting"
    exit 1
fi
```

### Production vs Development

```bash
#!/bin/bash

# Source logshuru
source logshuru

# Set different log levels based on environment
if [ "$ENVIRONMENT" = "production" ]; then
    set_log_level "WARNING"
else
    set_log_level "DEBUG"
fi

# Use the log function
log DEBUG "Detailed debugging information"
log INFO "Application initialized"
log ERROR "This appears in both environments"
```

## Configuration

### Default Log Level

The default log level is `PROCESS`. You can change this by:

1. Setting the `LOG_LEVEL` environment variable before running your script
2. Calling `set_log_level` after sourcing the script

### Colors

Set `LOGSHURU_COLOR` before starting the CLI or sourcing the library:

| Mode | Behavior |
| ---- | -------- |
| `auto` (default) | Emit colors only when the destination is a terminal, `NO_COLOR` is unset or empty, and `TERM` is not `dumb` |
| `always` | Emit colors even on redirected output, overriding `NO_COLOR` and `TERM=dumb` |
| `never` | Omit all logger-generated colors, even on a terminal |

```bash
LOGSHURU_COLOR=never logshuru INFO "Plain text"
LOGSHURU_COLOR=always logshuru INFO "Retain colors" > colored.log
NO_COLOR=1 logshuru INFO "Plain text in automatic mode"

# Configure library use before sourcing.
export LOGSHURU_COLOR=never
source logshuru
log INFO "Plain library output"
```

Mode names are case-insensitive. Unset or empty `LOGSHURU_COLOR` selects `auto`;
invalid nonempty values fail initialization with status `1` and a diagnostic on
stderr. Like `LOG_LEVEL`, the mode is read when the library is sourced; later
assignments alone do not change its active setting. In automatic mode, terminal
status, `NO_COLOR`, and `TERM` are evaluated at each output call, including
per-call redirections. Any nonempty `NO_COLOR` value, including `0`, disables
automatic colors; an empty value does not.

The same policy applies to help and colored invalid-call diagnostics, checking
their respective stdout or stderr destination. Startup configuration diagnostics
are plain text. Color controls affect logger-generated formatting, not escape
sequences supplied inside message text.

**Compatibility:** redirected output previously always contained ANSI colors.
Use `LOGSHURU_COLOR=always` to retain that behavior. Log records continue to use
stdout by default; usage and configuration diagnostics use stderr.

New output settings use the `LOGSHURU_*` namespace. The existing `LOG_LEVEL`
setting and `set_log_level` interface remain supported. Configuration is read at
CLI startup/library initialization, with explicit settings taking precedence
over automatic detection and defaults.

### Output Streams

Set `LOGSHURU_OUTPUT` before starting the CLI or sourcing the library:

| Mode | Log destination |
| ---- | --------------- |
| `stdout` (default) | Every level goes to stdout, preserving existing behavior |
| `stderr` | Every level goes to stderr, leaving stdout available for application data |
| `split` | TRACE, DEBUG, PROCESS, INFO, and SUCCESS go to stdout; WARNING, ERROR, and CRITICAL go to stderr |

```bash
LOGSHURU_OUTPUT=stderr logshuru INFO "Processing sample"
LOGSHURU_OUTPUT=split logshuru WARNING "Check sample quality"

# Keep logs out of data captured by command substitution.
export LOGSHURU_OUTPUT=stderr
source logshuru
sample_id=$(log INFO "Reading sample ID"; printf '%s' 'sample-42')
```

Mode names are case-insensitive. Unset or empty values select `stdout`; invalid
nonempty values fail initialization with status `1` and a diagnostic on stderr.
The active mode is initialized at startup/sourcing. Later assignments alone do
not change it; exported settings are inherited when a child sources the library.

Only log records are routed. Usage, invalid-call, and configuration diagnostics
always use stderr. Help, version information, and `get_log_level` results always
use stdout. The INFO notification from `set_log_level` is a log record and follows
the selected routing and filtering rules.

Automatic colors follow the selected stream's actual terminal status, including
per-call redirection. Writing to stderr does not itself indicate failure: a
successfully emitted ERROR or CRITICAL message still returns `0`. A failure to
write to the selected stream returns nonzero. Filtered messages write to neither
stream and continue to return `0`.

## Contributing

Contributions are welcome! Please feel free to submit a pull request.

### Running Tests

The regression suite uses [Bats-core](https://github.com/bats-core/bats-core)
1.5.0 or later. Bats is a development dependency, not a requirement for using
logshuru.

Install Bats using your package manager (for example, `sudo apt install bats` on
Debian/Ubuntu), or follow the
[Bats installation instructions](https://bats-core.readthedocs.io/en/stable/installation.html).
Check the installed version with `bats --version`; version 1.11.1 was used to
verify this suite.

From the repository root, run:

```bash
bash -n logshuru.sh
bats tests
```

The baseline suite covers:

| Test file | Coverage |
| --------- | -------- |
| `tests/log_levels.bats` | All eight levels at all eight thresholds in CLI and library modes (128 matrix cases), invalid levels at every threshold, and lowercase levels |
| `tests/messages.bats` | Literal backslashes, percent signs, quotes, shell metacharacters, tabs, Unicode, multiline content, whitespace, and every level's ANSI color |
| `tests/colors.bats` | Color modes, actual terminals and redirected output, `NO_COLOR` precedence, `TERM=dumb`, initialization errors, and independent stdout/stderr detection |
| `tests/output.bats` | All levels in all three stream modes for CLI/library calls (48 routing cases), selected/unused descriptor failures, filtering, initialization, child processes, data separation, and selected-stream colors |
| `tests/configuration.bats` | Environment defaults, normalization, invalid initialization, setter exports, and unchanged settings after rejected input |
| `tests/arguments.bats` | Missing/empty arguments, multiple message arguments, setter argument counts, and help/version flags, including nounset mode |
| `tests/child_shells.bats` | Explicit initialization, inherited thresholds, state isolation, and subshell usage |
| `tests/context.bats` | Real caller basenames, immediate functions, actual call lines, sourced helpers, subshells, and CLI placeholders |
| `tests/strict_mode.bats` | Full strict-mode workflows, shell-option preservation, handled/unhandled failures, pipelines, and failed writes |
| `tests/exit_status.bats` | Output failures without errexit, filtered messages with closed stdout, getter failures, and help/version write failures |

Invalid levels return status `1` with a diagnostic on stderr regardless of the
configured threshold. Valid messages return `0` when emitted or filtered,
including ERROR and CRITICAL messages; applications decide whether to exit after
logging an error. Output failures return nonzero, including failures writing
help, version information, or the current log level. Filtered messages do not
write output and succeed even if both stdout and stderr are closed.

Terminal-color tests use the util-linux `script` command, included on the Linux
CI runner. Install `util-linux` to run those tests locally; they are skipped if
`script` is unavailable. This is a test dependency, not a logging dependency.
Other tests explicitly select their expected color and output modes, so their
expectations do not depend on the terminal or output configuration running Bats.

### Static Analysis

Use [ShellCheck](https://www.shellcheck.net/) 0.10.0 or later to check the logger,
Bats tests, test helpers, and fixtures. Version 0.10.0 was used to verify the
current code. ShellCheck is a development tool, not a logging dependency.

Install it with your package manager (for example, `sudo apt install shellcheck`
on Debian/Ubuntu), or follow the
[ShellCheck installation instructions](https://github.com/koalaman/shellcheck#installing).
Check the installed version with `shellcheck --version`.

From the repository root, run:

```bash
shellcheck logshuru.sh tests/*.bats tests/*.bash tests/fixtures/*.bash
```

The repository's `.shellcheckrc` enables analysis of annotated source files and
resolves their paths relative to the file being checked. Test-specific comments
explain the limited exclusions for intentional child-shell/literal quoting and
Bats test isolation. No diagnostic exclusions are applied to the logger itself.

### Formatting

Use [shfmt](https://github.com/mvdan/sh) **3.10.0** to reproduce the verified
formatting. Install the matching binary for your platform from the
[shfmt releases](https://github.com/mvdan/sh/releases/tag/v3.10.0), and check it
with `shfmt --version`. This is a development tool, not a logging dependency.

Shell and Bats files use tabs, LF line endings, and a final newline, with no
trailing whitespace. `.editorconfig` records these settings for editors and
shfmt; tabs have a four-column display width in supporting editors. Other shell
layout follows shfmt defaults.

From the repository root, check formatting without changing files:

```bash
shfmt -ln bash -d logshuru.sh tests/*.bash tests/fixtures/*.bash
shfmt -ln bats -d tests/*.bats
```

The explicit language modes let shfmt parse Bash helpers and Bats `@test` blocks
correctly. To apply formatting, use the same file lists with `-w`:

```bash
shfmt -ln bash -w logshuru.sh tests/*.bash tests/fixtures/*.bash
shfmt -ln bats -w tests/*.bats
```

### Running All Checks

With Bats, ShellCheck, and shfmt installed, run these commands from the repository
root. Syntax errors, lint findings, formatting differences, or failing tests
produce a nonzero status:

```bash
set -e
for file in logshuru.sh tests/*.bash tests/fixtures/*.bash; do
    bash -n "$file"
done
shellcheck logshuru.sh tests/*.bats tests/*.bash tests/fixtures/*.bash
shfmt -ln bash -d logshuru.sh tests/*.bash tests/fixtures/*.bash
shfmt -ln bats -d tests/*.bats
bats tests
```

### Continuous Integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on pushes, pull
requests, and manual dispatches. Its Ubuntu 22.04 job uses the same syntax,
ShellCheck, Bash/Bats formatting, and Bats commands documented above, with
separate steps for clear failure reporting.

Development tools are pinned to:

| Tool | Version |
| ---- | ------- |
| Bats-core | 1.11.1 |
| ShellCheck | 0.10.0 |
| shfmt | 3.10.0 |

The workflow installs these tools in the runner's temporary directory and prints
the Bash, coreutils, and tool versions in its logs. Tests run with `LC_ALL=C.UTF-8`
and `TZ=UTC`. The runner also reports the util-linux `script` version used for
terminal tests. Repository access is read-only, and superseded runs on the same
workflow/ref are cancelled.

To reproduce its checks locally, install the versions above and use
[Running All Checks](#running-all-checks). GitHub starts the workflow once the
workflow file and project changes are pushed to the repository.

## Acknowledgments

Inspired by the excellent [loguru](https://github.com/Delgan/loguru) library for Python.
