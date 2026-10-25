# Releasing logshuru

## Version and compatibility policy

Use semantic versions and tags of the form `vMAJOR.MINOR.PATCH`.

- Major: incompatible CLI/library, configuration, output, exit-status, or minimum
  Bash changes.
- Minor: backward-compatible features.
- Patch: backward-compatible bug fixes.
- The public library functions are `log`, `set_log_level`, and `get_log_level`.
  `_logshuru_*` names are private implementation details.

The current version is `2.0.0`. Its changelog section collects all changes since
the historical `1.0.0` baseline, including previously committed compatibility
changes. Future development snapshots should use the next planned `-dev` version.

## Prepare

1. Review the complete changes and move the unreleased changelog section to a
   dated version heading. Make migration instructions prominent.
2. Set `_logshuru_version` in `logshuru.sh` to the release version without `v` or
   `-dev`, update version assertions in `tests/library.bats` and `tests/json.bats`,
   and update the README's development/release status.
3. Run all checks documented in the README, including the full Bats suite on
   Bash 4.2, 4.4, system Bash 5.1, and Bash 5.2. Confirm the hosted workflow passes
   for the final release commit.
4. Review `git status`, the full diff, and recent history; commit the finalized
   release changes when authorized. Record the full 40-character commit SHA.

A separate installer is unnecessary for the current single-file distribution:
`install -m 755` supports both CLI and library use. Keep installation instructions
explicit and checksum-verified.

## Tag and publish

Only create/push tags or publish a GitHub release when explicitly requested.
Use an annotated version tag pointing at the verified release commit. Do not move
an existing release tag to different contents.

From that exact commit, produce the checksum asset:

```bash
sha256sum logshuru.sh > SHA256SUMS
sha256sum --check --strict SHA256SUMS
bash logshuru.sh --version
```

Publish `logshuru.sh` and `SHA256SUMS` as release assets using GitHub CLI (`gh
release create` or `gh release upload`). Release notes should contain:

- The version, full commit SHA, supported Bash minimum, and migration notes.
- The script's SHA-256 copied from `SHA256SUMS`.
- Links to the changelog and the version-pinned script/checksum assets.
- Installation commands with concrete `LOGSHURU_REVISION` and `LOGSHURU_SHA256`
  values for the README's pinned-download procedure.

Generate checksums after finalizing the version. Do not reuse a checksum from a
development snapshot or checksum a different working-tree copy.

## Verify the published installation

1. Download `logshuru.sh` and `SHA256SUMS` from that specific version's release
   assets into a clean temporary directory. Verify with
   `sha256sum --check --strict SHA256SUMS`.
2. Download the raw script at the recorded full commit SHA and confirm it has the
   same checksum as the release asset. Use the README's pinned installer with a
   temporary `HOME` to avoid replacing a local installation.
3. Confirm `bash "$HOME/.local/bin/logshuru" --version` reports the final version;
   run a CLI text/JSON event and source the installed file through a loader
   function under strict mode, then check filtering and the setter/getter.
4. Publish the concrete pinned revision/checksum in the README once the release
   is available. Only then announce the release as installable and verified.

For subsequent development, create a new unreleased changelog section and advance
the script and version assertions to the next planned `-dev` version.
