# Design decisions

[Quick start](../README.md) · [Usage contract](USAGE.md) · [Configuration reference](CONFIGURATION.md)

This document explains why logshuru behaves as it does. The usage and
configuration guides own the detailed user-facing contract; examples and tests
should agree with those references.

## A small general-purpose logger

Applications own command execution, domain logic, retries, and workflow status.
logshuru supplies records and reports logging failures. Severity is not an exit
policy: an application can recover from an ERROR event, while a failed log write
can still matter operationally. The [command example](../examples/README.md)
explicitly chooses best-effort lifecycle logging after successful initialization.

Only `log`, `set_log_level`, and `get_log_level` are public functions. Private
`_logshuru_*` state/helpers avoid collisions with common caller names. Their
implementation may change without becoming another supported API.

## Explicit initialization

Configuration is captured when starting/sourcing so accidental later environment
assignments do not silently reconfigure a running script. The setter provides an
explicit level update and exports the choice for future child initialization.
Ambient terminal state remains dynamic because per-call redirections matter.
See [initialization rules](CONFIGURATION.md#initialization).

Each new Bash process sources the library rather than inheriting incomplete
exported functions without their helpers/arrays. Global associative arrays allow
loader-function sourcing. Declaration and assignment are separate because Bash
4.2's combined form initializes empty global arrays in that context. This is the
reason for the Bash 4.2 floor; verified baselines live in the
[installation guide](INSTALLATION.md#platform-compatibility).

Initialization failure is not transactional restoration of prior state. Callers
must handle a failed source before using the library. Sourcing does not change
caller shell options; strict-mode recovery remains the application's choice.

## Truthful context and literal data

A private emitter receives an explicit local frame offset so public log/setter
calls identify the application without mutable global offsets. Application
wrappers are not skipped. CLI records use explicit unavailable-location markers
rather than suggesting the logger's internals identify the invoking script.
See [source context](USAGE.md#source-context).

Fixed printf formats keep message/context data separate from color escapes.
Space joining uses local IFS rather than depending on caller state. Text retains
literal multiline content; JSON provides single-line framing for untrusted data.

The JSON serializer stays in Bash to avoid a language-package/runtime dependency.
Byte-wise UTF-8 validation gives explicit malformed-input failure, at the cost of
CPU time for long strings. jq is an independent test/consumer oracle. See the
[JSON reference](CONFIGURATION.md#json-lines) for schema and encoding details.

## Predictable destinations

stdout remains the default for compatibility; explicit stderr/split routing
supports scripts whose stdout is application data. Automatic colors inspect the
actual selected descriptor at emission time. File copies and JSON suppress
logger colors rather than contaminating machine-consumed output.

One date result is reused across stream/file copies so metadata agrees. GNU date
retains format/timezone functionality across the supported Bash versions.
Overrides apply to date without mutating the caller's timezone environment.

File logging duplicates records and attempts destinations independently: a failed
stream should not prevent a useful file copy, or vice versa. No rollback can undo
bytes already written. Per-event append keeps file handling small; rotation,
retention, locking, and transactional delivery remain external responsibilities.
Detailed failure semantics live in the [file reference](CONFIGURATION.md#file-logging).

## Documentation and maintenance

Durable decisions belong in repository documentation, reviewed alongside code
and available at release tags. The README is a quick-start page, not the complete
manual. Keep each detailed contract in its owning guide and link to it elsewhere.
Local plans may keep checklists/history, but are not the only record of decisions.

Changes to public behavior or the interpreter minimum follow the compatibility
rules in [RELEASING.md](../RELEASING.md). Keep tests and
[local/CI checks](../CONTRIBUTING.md#running-all-checks) aligned, including new
example files and runtime-matrix syntax checks.
