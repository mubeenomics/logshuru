# Changelog

Changes are recorded here before a release is published. Versions follow
[Semantic Versioning](https://semver.org/); see [RELEASING.md](RELEASING.md).

## Unreleased — planned 2.0.0

Development snapshots report `2.0.0-dev`. This section includes the reliability
and output-control work previously committed while the script still reported
`1.0.0`; it does not imply those changes were published as a tagged release.

### Breaking changes and migration

- Require Bash 4.2 or later for globally initialized associative arrays. Earlier
  Bash versions fail initialization with a clear diagnostic.
- Reserve `_logshuru_*` for private state and helpers. Only `log`, `set_log_level`,
  and `get_log_level` are public library functions. Applications using former
  internals such as `COLORS`, `LOG_LEVELS`, `VERSION`, `main`, or `should_log`
  must stop depending on them; sourcing now preserves those caller names.
- Default to automatic colors rather than always-colored redirected output.
  Set `LOGSHURU_COLOR=always` to restore the old behavior.
- Send usage/configuration diagnostics to stderr. Log records still use stdout
  by default; help, version, and getter output remain on stdout.
- Require each new Bash process to source the library explicitly. Incomplete
  automatic function exports have been removed.
- Reject invalid initial levels and missing message arguments with nonzero
  status. An explicitly empty message remains valid.
- Render message backslashes literally rather than interpreting them as escapes.
  Use ANSI-C quoting when deliberately supplying tabs or newlines.
- Propagate output and timestamp failures as nonzero statuses, including setter
  notifications. A valid setter change remains active if its notification fails.

### Added

- Color controls (`auto`, `always`, `never`), `NO_COLOR`, and terminal detection.
- stdout, stderr, and split output routing.
- Configurable GNU-date timestamp formats and explicit UTC/IANA timezone overrides.
- Optional append-only file copies with independent destination failure reporting.
- Optional JSON Lines with pure-Bash escaping and UTF-8 validation.
- Bats regression coverage, ShellCheck, shfmt, and GitHub Actions checks.
- Full runtime coverage for Bash 4.2, 4.4, and 5.2 alongside system Bash 5.1.
- Pinned SHA-256 verification of downloaded CI tools and Bash source archives.
- Pinned-download installation instructions and a documented release procedure.

### Fixed

- Keep initialized arrays available after sourcing inside a loader function,
  including Bash 4.2's declaration/assignment edge case.
- Avoid overwriting generic caller variables and helper functions.
- Join message arguments with spaces regardless of caller `IFS`, preserving
  empty fragments and the caller's setting.
- Normalize and validate levels consistently before filtering; print accepted
  levels in severity order in every diagnostic.
- Preserve strict-mode workflows and report accurate caller context. CLI records
  explicitly use `cli:cli:0`; unavailable source lines use `0`.
- Use the executable basename for `--version`, consistent with CLI help.

### Performance and documentation

- Replace `basename` processes with Bash parameter expansion throughout the
  logger, removing the external dependency.
- Document text-mode record-forging risks for untrusted input and JSON mode's
  single-line framing, along with pure-Bash serialization overhead.
- Upgrade verified ShellCheck to 0.11.0 and annotate indirectly invoked test stubs.

## Historical baseline — 1.0.0

The original script reported `1.0.0` and provided eight colored log levels,
threshold filtering, timestamps, caller context, and CLI/library entry points.
No release date or tag is assigned here retroactively.
