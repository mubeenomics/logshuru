# logshuru

A general-purpose Bash logger, inspired by Python's
[loguru](https://github.com/Delgan/loguru). Use it as a CLI or source it in your
scripts for colored text or JSON Lines with timestamps and caller context.

**Current release: [v2.0.0](https://github.com/mubeenomics/logshuru/releases/tag/v2.0.0)**
· [Changelog](CHANGELOG.md)

## Features

- Eight severity levels with configurable filtering.
- File, function, and line context for library calls.
- Automatic terminal colors, stdout/stderr/split routing, and optional file copies.
- Custom timestamps/timezones and Bash-only UTF-8 JSON serialization.
- Strict-mode support and explicit failure statuses.

## Requirements

**Bash 4.2+** and **GNU-compatible `date`** with millisecond formatting (`%3N`).
Default macOS Bash 3.2 and BSD date do not meet these requirements. See
[installation and platform details](docs/INSTALLATION.md).

## Install

Download and verify the versioned release before installing in your user-local
bin directory. Run this block in Bash:

```bash
(
    set -euo pipefail
    download_dir=$(mktemp -d)
    trap 'rm -rf -- "$download_dir"' EXIT
    curl --fail --silent --show-error --location \
        https://github.com/mubeenomics/logshuru/releases/download/v2.0.0/logshuru.sh \
        --output "$download_dir/logshuru.sh"
    printf '%s  %s\n' \
        520cd796f8c2ad4a2a4a8298566731ba17c5e10a7e3392fdfa854f6bd5c2db6e \
        "$download_dir/logshuru.sh" | sha256sum --check --strict
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$download_dir/logshuru.sh" "$HOME/.local/bin/logshuru"
)
```

Add `$HOME/.local/bin` to PATH for CLI use. For commit-pinned downloads, checkout
installation, and environment checks, see the [installation guide](docs/INSTALLATION.md).

## Quick start

### CLI

```bash
logshuru INFO "Application started"
LOG_LEVEL=DEBUG logshuru DEBUG "Diagnostic information"
logshuru --help
```

CLI records use `cli:cli:0`; a separate process cannot inspect its invoking
shell's source location.

### Library

```bash
#!/bin/bash
set -euo pipefail
source "$HOME/.local/bin/logshuru"

log INFO "Application started"
set_log_level DEBUG
log DEBUG "Diagnostic information"
printf 'Current level: %s\n' "$(get_log_level)"
```

Library calls report the application file, immediate caller function, and line:

```text
2026-10-25 14:32:45.123 | INFO     | app.sh:main:5 - Application started
```

Public functions are `log`, `set_log_level`, and `get_log_level`.
See the [usage guide](docs/USAGE.md) for arguments, strict mode, child shells,
source context, and recipes.

## Levels and configuration

Severity increases left to right:

```text
TRACE → DEBUG → PROCESS → INFO → SUCCESS → WARNING → ERROR → CRITICAL
```

The default threshold is `PROCESS`. Set environment configuration **before**
starting the CLI or sourcing the library. To change an initialized library's
threshold, use `set_log_level`.

| Setting | Default | Purpose |
| --- | --- | --- |
| `LOG_LEVEL` | `PROCESS` | Minimum severity |
| `LOGSHURU_COLOR` | `auto` | auto / always / never |
| `LOGSHURU_OUTPUT` | `stdout` | stdout / stderr / split |
| `LOGSHURU_FORMAT` | `text` | text / json |
| `LOGSHURU_TIMESTAMP_FORMAT` | `%F %T.%3N` | GNU-date format |
| `LOGSHURU_TZ` | Inherited TZ/local time | UTC or installed IANA zone |
| `LOGSHURU_FILE` | Disabled | Append a duplicate record to a file |

```bash
LOGSHURU_OUTPUT=stderr logshuru INFO "Keep stdout available for data"
LOGSHURU_FORMAT=json logshuru INFO "Machine-readable event"
```

The [configuration reference](docs/CONFIGURATION.md) covers defaults, validation,
precedence, stream routing, colors, timestamps, file failures, and JSON schema.

## Important behavior

- Successfully emitted and filtered events return `0`, including ERROR/CRITICAL.
  The application decides whether an error event should terminate its workflow.
- Invalid calls, initialization errors, and write failures return nonzero and
  can terminate unhandled strict-mode scripts.
- Records default to stdout; diagnostics use stderr. Choose
  `LOGSHURU_OUTPUT=stderr` to keep logs separate from application data.
- Text preserves real newlines and terminal escapes. Use JSON for single-line
  framing of untrusted messages or metadata.
- Each new Bash process must source the library; functions are not automatically
  exported. `_logshuru_*` names are private implementation details.

## Documentation

- [Installation](docs/INSTALLATION.md) — downloads, checksums, dependencies, platforms.
- [Usage](docs/USAGE.md) — CLI/library APIs, statuses, strict mode, context, recipes.
- [Configuration](docs/CONFIGURATION.md) — full settings and output reference.
- [Command-runner example](examples/README.md) — lifecycle logs around an arbitrary command.
- [Design](docs/DESIGN.md) — rationale and implementation boundaries.
- [Contributing](CONTRIBUTING.md) — development tools, tests, formatting, and CI.
- [Changelog](CHANGELOG.md) · [Release procedure](RELEASING.md)

Contributions are welcome. logshuru stays general-purpose; domain-specific
workflow logic belongs in the applications using it.

## Acknowledgments

Inspired by the excellent [loguru](https://github.com/Delgan/loguru) library for Python.
