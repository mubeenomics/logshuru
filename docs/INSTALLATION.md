# Installation and platform requirements

[Quick start](../README.md) · [Usage](USAGE.md) · [Configuration](CONFIGURATION.md)

## Runtime requirements

- **Bash 4.2 or later.** Global associative arrays (`declare -gA`) allow sourcing
  inside loader functions. Older Bash versions fail initialization with a
  diagnostic. POSIX sh, Dash, and Zsh are not supported interpreters.
- **GNU-compatible `date` on PATH.** The default `date +"%F %T.%3N"` must support
  `%F`, `%T`, and `%3N` for millisecond timestamps. GNU coreutils provides it.
- **Installed timezone data for named overrides.** For example,
  `LOGSHURU_TZ=Asia/Kolkata` requires that zone under `/usr/share/zoneinfo` or the
  directory selected by `TZDIR`. Linux distributions normally provide `tzdata`.
  The explicit `UTC` override needs no timezone database.

ANSI-compatible terminals display colors, but a terminal is not required. The
default `auto` color mode omits logger colors when output is redirected.

To inspect your environment:

```bash
bash --version
command -v date
date +"%F %T.%3N"
```

The last command should print `YYYY-MM-DD HH:MM:SS.mmm`, with three numeric
fractional-second digits. Timestamps default to local time, honoring inherited
`TZ`; see [timestamp configuration](CONFIGURATION.md#timestamps).

## Platform compatibility

CI targets **Ubuntu 22.04 on x86_64** with GNU coreutils. The full suite runs on
system Bash 5.1 and source-built Bash 4.2, 4.4, and 5.2. Local verification also
covers those source-built versions and Bash 5.1.16.

Source builds deliberately use the original, unpatched **4.2.0, 4.4.0, and 5.2.0**
tarballs to exercise language-feature baselines; distribution builds generally
include later patches. Other platforms are not covered by CI.

The default Bash 3.2 and BSD date shipped with macOS do not meet the requirements.
Provide a newer Bash and a GNU-compatible command named `date` on PATH. Installing
only `gdate` does not change the logger's `date` invocation.

The script uses `#!/bin/bash`. If a suitable Bash is installed elsewhere, invoke
that interpreter explicitly or source the library from a script running under it.

## Version-pinned download

The following installs **v2.0.0**, pinned to its full release commit and published
SHA-256. It stops on download or checksum failure. To choose another reviewed
revision, set both `LOGSHURU_REVISION` and `LOGSHURU_SHA256` beforehand using
values from its trusted checkout or release notes.

```bash
(
    set -euo pipefail
    LOGSHURU_REVISION=${LOGSHURU_REVISION:-494e69ce4f3199ec04e6e6c29e283d06fd09713d}
    LOGSHURU_SHA256=${LOGSHURU_SHA256:-520cd796f8c2ad4a2a4a8298566731ba17c5e10a7e3392fdfa854f6bd5c2db6e}
    [[ "$LOGSHURU_REVISION" =~ ^[0-9a-f]{40}$ ]]
    [[ "$LOGSHURU_SHA256" =~ ^[0-9a-f]{64}$ ]]
    download_dir=$(mktemp -d)
    trap 'rm -rf -- "$download_dir"' EXIT
    curl --fail --silent --show-error --location \
        "https://raw.githubusercontent.com/mubeenomics/logshuru/${LOGSHURU_REVISION}/logshuru.sh" \
        --output "$download_dir/logshuru.sh"
    printf '%s  %s\n' "$LOGSHURU_SHA256" "$download_dir/logshuru.sh" | sha256sum --check --strict
    bash -n "$download_dir/logshuru.sh"
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$download_dir/logshuru.sh" "$HOME/.local/bin/logshuru"
)
```

Add `$HOME/.local/bin` to PATH if needed. For library use, source
`"$HOME/.local/bin/logshuru"` directly.

## Install from a checkout

From a reviewed checkout:

```bash
mkdir -p "$HOME/.local/bin"
install -m 755 logshuru.sh "$HOME/.local/bin/logshuru"
```

For system-wide installation, use an appropriate writable directory on PATH, or
run `sudo install -m 755 logshuru.sh /usr/local/bin/logshuru`.

## Release assets and integrity

The [v2.0.0 release](https://github.com/mubeenomics/logshuru/releases/tag/v2.0.0)
provides `logshuru.sh` and `SHA256SUMS`. The assets and commit-pinned installation
have been verified against the same hash:

```text
520cd796f8c2ad4a2a4a8298566731ba17c5e10a7e3392fdfa854f6bd5c2db6e
```

When downloading both assets into one directory, verify them with
`sha256sum --check --strict SHA256SUMS` before installation. Maintainer procedures
are in [RELEASING.md](../RELEASING.md).

Download/installation tools such as curl, sha256sum, mktemp, mkdir, rm, and install
are not logging dependencies. Bats, jq, ShellCheck, and shfmt are development tools;
see [Contributing](../CONTRIBUTING.md).
