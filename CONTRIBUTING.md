# Contributing to logshuru

Contributions are welcome. See the [design decisions](docs/DESIGN.md) and
[configuration reference](docs/CONFIGURATION.md) before changing behavior.
Run commands below from the repository root.

## Development tools

| Tool | Requirement | Verified / CI version |
| --- | --- | --- |
| Bats-core | 1.5.0 or later | 1.11.1 |
| jq | 1.6 or later | Runner-provided |
| ShellCheck | 0.11.0 or later | 0.11.0 |
| shfmt | Use the matching version for reproducible formatting | 3.10.0 |
| util-linux script | Optional locally; required for terminal-color coverage | Runner-provided |

These are development dependencies, not logger runtime dependencies. jq supplies
an independent JSON parser/round-trip oracle; the logger does not invoke jq,
Python, or Node.js to serialize records.

On Debian/Ubuntu, Bats, jq, ShellCheck, and util-linux are available through the
package manager (for example, `sudo apt install bats jq shellcheck util-linux`).
Check versions; distribution packages may differ from the CI pins. Upstream
installation instructions:

- [Bats-core](https://bats-core.readthedocs.io/en/stable/installation.html)
- [ShellCheck](https://github.com/koalaman/shellcheck#installing)
- [shfmt 3.10.0 binaries](https://github.com/mvdan/sh/releases/tag/v3.10.0)

```bash
bats --version
jq --version
shellcheck --version
shfmt --version
script --version
```

## Running tests

```bash
for file in logshuru.sh examples/*.sh tests/*.bash tests/fixtures/*.bash; do
    bash -n "$file"
done
bats tests
```

Tests select their output modes and clear relevant settings so expectations do
not depend on the environment launching Bats. Terminal tests use util-linux
`script` and skip when it is unavailable. The regular-file permissions test skips
under root because root can bypass its intended failure.

| Test file | Coverage |
| --- | --- |
| `tests/log_levels.bats` | Eight levels at eight thresholds, CLI/library matrix, invalid/lowercase levels |
| `tests/messages.bats` | Literal backslashes, percent signs, quotes, metacharacters, Unicode, multiline content, colors |
| `tests/colors.bats` | Modes, real terminals/redirection, NO_COLOR, TERM=dumb, descriptor independence |
| `tests/output.bats` | All level/stream-mode combinations, descriptor failures, children, data separation |
| `tests/timestamps.bats` | Formats, UTC/IANA/inherited zones, TZDIR, literal rendering, date failure |
| `tests/files.bats` | Append/duplication, content/paths, snapshots, children, independent destination failures |
| `tests/json.bats` | Schema, C0 escapes, UTF-8 boundaries/rejection, round trips, framing, routing/file copies |
| `tests/configuration.bats` | Defaults, normalization, initialization errors, setter exports/state preservation |
| `tests/arguments.bats` | Missing/empty/multiple arguments, setter counts, flags, nounset |
| `tests/child_shells.bats` | Explicit initialization, inherited thresholds, isolation, subshells |
| `tests/context.bats` | Caller files/functions/lines, wrappers, CLI markers, setter text/JSON/file context |
| `tests/library.bats` | Loader-function sourcing, namespaces, IFS joins, ordered diagnostics, version/basename-free operation |
| `tests/strict_mode.bats` | Strict workflows/options, handled/unhandled failures, pipelines, failed writes |
| `tests/exit_status.bats` | Output/getter/help/version failures and filtered closed descriptors |
| `tests/examples.bats` | Command-runner argv, streams/stdin, statuses, working directories, configuration/log failures |

The full suite covers 128 level/threshold cases across CLI/library modes and 48
level/stream routing cases, in addition to the targeted edge cases above.

## Static analysis

```bash
shellcheck logshuru.sh examples/*.sh tests/*.bats tests/*.bash tests/fixtures/*.bash
```

[`.shellcheckrc`](.shellcheckrc) follows annotated external sources with paths
relative to the checked file. Test comments explain intentional child-shell
quoting and Bats isolation exclusions. No diagnostic exclusions apply to the
logger itself.

## Formatting

Shell and Bats files use tabs (four-column display width), LF endings, a final
newline, and no trailing whitespace. [`.editorconfig`](.editorconfig) records
these settings. Other layout follows shfmt defaults.

Check without modifying files:

```bash
shfmt -ln bash -d logshuru.sh examples/*.sh tests/*.bash tests/fixtures/*.bash
shfmt -ln bats -d tests/*.bats
```

Use explicit Bash/Bats modes so helpers and @test blocks parse correctly. To apply:

```bash
shfmt -ln bash -w logshuru.sh examples/*.sh tests/*.bash tests/fixtures/*.bash
shfmt -ln bats -w tests/*.bats
```

## Running all checks

With the tools installed, syntax/lint/format differences or failing tests return
nonzero:

```bash
set -e
for file in logshuru.sh examples/*.sh tests/*.bash tests/fixtures/*.bash; do
    bash -n "$file"
done
shellcheck logshuru.sh examples/*.sh tests/*.bats tests/*.bash tests/fixtures/*.bash
shfmt -ln bash -d logshuru.sh examples/*.sh tests/*.bash tests/fixtures/*.bash
shfmt -ln bats -d tests/*.bats
bats tests
```

Add new example shell files to applicable local and CI file lists, including
runtime-matrix syntax checks. Keep documented commands aligned with the workflow.
Documentation-only edits need link/anchor, command-example, and whitespace checks;
a full runtime rerun is needed when executable code or its behavior changes.

## Continuous integration

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) runs on push, pull request,
and manual dispatch. The Ubuntu 22.04 checks job runs the syntax, ShellCheck,
Bash/Bats formatting, and Bats commands above as separate steps.

Runtime jobs build Bash 4.2, 4.4, and 5.2 from pinned GNU archives and run syntax
checks plus the full suite. Each selected interpreter is first on PATH for Bats
and its child shells; its version is asserted before testing. See
[platform compatibility](docs/INSTALLATION.md#platform-compatibility) for the
original unpatched build baselines.

All downloaded tools/source archives are checked against pinned SHA-256 hashes
before extraction or execution. Update version and checksum together after
reviewing the upstream artifact. Tools install into the runner's temporary
directory. Logs report Bash, coreutils, and development-tool versions, including
script and jq. Tests use `LC_ALL=C.UTF-8` and `TZ=UTC`.

Repository access is read-only, checkout credentials are not persisted, and
superseded runs on the same workflow/ref are cancelled. GitHub starts the updated
workflow once changes are pushed. Workflow changes can additionally be validated
with [actionlint](https://github.com/rhysd/actionlint).

## Compatibility and releases

Keep documented behavior and regression coverage aligned. Record changes in
[CHANGELOG.md](CHANGELOG.md); compatibility rules and publication procedures live
in [RELEASING.md](RELEASING.md). Use that guide for tags, assets, checksums, and
published-install verification.
