#!/usr/bin/env bats

# Child Bash commands expand their own variables; Bats isolates test state.
# shellcheck disable=SC2016,SC2030,SC2031

bats_require_minimum_version 1.5.0

# shellcheck source=test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	export LOG_LEVEL=PROCESS LOGSHURU_COLOR=never LOGSHURU_OUTPUT=stdout TZ=UTC0
	unset LOGSHURU_TIMESTAMP_FORMAT LOGSHURU_TZ TZDIR
	unset LOGSHURU_FILE
	export LOGSHURU_FORMAT=text
}

freeze_time() {
	# Exercise real GNU date formatting/timezones against a fixed instant.
	# Exported stubs are invoked indirectly by the child Bash processes.
	# shellcheck disable=SC2317
	date() { command date --date='2026-10-23T10:30:00.123Z' "$@"; }
	export -f date
}

@test "unset and empty timestamp settings preserve the existing default format" {
	freeze_time
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "default timestamp"
		[ "$status" -eq 0 ]
		[[ "$output" == '2026-10-23 10:30:00.123 | '* ]]
		[ -z "$stderr" ]
		export LOGSHURU_TIMESTAMP_FORMAT="" LOGSHURU_TZ=""
		run --separate-stderr invoke_logger "$mode" INFO "empty settings"
		[ "$status" -eq 0 ]
		[[ "$output" == '2026-10-23 10:30:00.123 | '* ]]
		[ -z "$stderr" ]
		unset LOGSHURU_TIMESTAMP_FORMAT LOGSHURU_TZ
	done
}

@test "custom UTC timestamp format works in CLI and library modes" {
	freeze_time
	export LOGSHURU_TIMESTAMP_FORMAT='%Y-%m-%dT%H:%M:%SZ' LOGSHURU_TZ=UTC
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "custom timestamp"
		[ "$status" -eq 0 ]
		[[ "$output" == '2026-10-23T10:30:00Z | '* ]]
		[ -z "$stderr" ]
	done
}

@test "timestamp format literals backslashes and percent signs are not reinterpreted" {
	freeze_time
	export LOGSHURU_TIMESTAMP_FORMAT='literal \n %% %Y'
	run --separate-stderr invoke_logger library INFO message
	[ "$status" -eq 0 ]
	[[ "$output" == 'literal \n % 2026 | '* ]]
	[ -z "$stderr" ]
}

@test "without an override timestamps retain inherited TZ behavior" {
	freeze_time
	export TZ=EST5
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "inherited timezone"
		[ "$status" -eq 0 ]
		[[ "$output" == '2026-10-23 05:30:00.123 | '* ]]
		[ -z "$stderr" ]
	done
}

@test "explicit UTC overrides ambient TZ without changing the caller environment" {
	freeze_time
	export TZ=EST5 LOGSHURU_TZ=UTC LOGSHURU_TIMESTAMP_FORMAT='%H:%M:%S %z'
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		[[ "$TZ" == EST5 ]]
		log INFO "override"
		[[ "$TZ" == EST5 ]]
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == '10:30:00 +0000 | '* ]]
	[ -z "$stderr" ]
}

@test "installed IANA timezones support non-whole-hour offsets in both modes" {
	freeze_time
	export LOGSHURU_TZ=Asia/Kolkata LOGSHURU_TIMESTAMP_FORMAT='%H:%M:%S %z'
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "named timezone"
		[ "$status" -eq 0 ]
		[[ "$output" == '16:00:00 +0530 | '* ]]
		[ -z "$stderr" ]
	done
}

@test "invalid explicit timezones fail CLI and sourced initialization cleanly" {
	for LOGSHURU_TZ in Missing/Zone ' UTC ' UTC0 ../UTC /etc/passwd; do
		export LOGSHURU_TZ
		run --separate-stderr invoke_logger cli INFO "must not be emitted"
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Invalid LOGSHURU_TZ:"*"$LOGSHURU_TZ"* ]]
		run --separate-stderr bash -euo pipefail -c \
			'if source "$1"; then exit 99; fi; printf "caller continued\n"' bash "$LOGSHURU"
		[ "$status" -eq 0 ]
		[ "$output" = 'caller continued' ]
		[[ "$stderr" == *"Invalid LOGSHURU_TZ:"* ]]
	done
}

@test "timestamp settings are snapshotted at source time and inherited by children" {
	freeze_time
	export LOGSHURU_TZ=UTC LOGSHURU_TIMESTAMP_FORMAT='%H:%M %z'
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		bash -euo pipefail -c '\''source "$1"; log INFO "child timestamp"'\'' bash "$1"
		export LOGSHURU_TZ=Asia/Kolkata LOGSHURU_TIMESTAMP_FORMAT=changed
		log INFO "parent timestamp"
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == '10:30 +0000 | '*"child timestamp"$'\n''10:30 +0000 | '*"parent timestamp" ]]
	[ -z "$stderr" ]
}

@test "timestamp settings compose with colors stderr routing and strict mode" {
	freeze_time
	export LOGSHURU_TZ=UTC LOGSHURU_TIMESTAMP_FORMAT='%H:%M' LOGSHURU_COLOR=always LOGSHURU_OUTPUT=stderr
	run --separate-stderr bash -euo pipefail -c 'source "$1"; log ERROR "routed timestamp"' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[[ "$stderr" == $'\e[0;32m10:30\e[0m | '* ]]
	[[ "$stderr" == *"routed timestamp"$'\e[0m' ]]
}

@test "date failures return nonzero and do not emit incomplete log records" {
	# Exported stub is invoked indirectly by the child Bash processes.
	# shellcheck disable=SC2317
	# Invoked indirectly by the sourced logger.
	# shellcheck disable=SC2329
	date() { return 23; }
	export -f date
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "must not be emitted"
		[ "$status" -ne 0 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Failed to generate log timestamp"* ]]
	done
}

@test "handled setter calls propagate timestamp-generation failures" {
	# Exported stub is invoked indirectly by the child Bash process.
	# shellcheck disable=SC2317
	# Invoked indirectly by the sourced logger.
	# shellcheck disable=SC2329
	date() { return 23; }
	export -f date
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		if set_log_level DEBUG; then exit 99; fi
		[[ "$(get_log_level)" == DEBUG ]]
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[[ "$stderr" == *"Failed to generate log timestamp"* ]]
}

@test "filtered messages do not invoke date or fail when it is unavailable" {
	# Exported stub would be invoked indirectly if filtering were broken.
	# shellcheck disable=SC2317
	# Invoked indirectly by the sourced logger.
	# shellcheck disable=SC2329
	date() { return 23; }
	export -f date
	export LOG_LEVEL=ERROR
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO filtered
		[ "$status" -eq 0 ]
		[ -z "$output" ]
		[ -z "$stderr" ]
	done
}

@test "explicit UTC does not require an installed timezone database" {
	freeze_time
	export LOGSHURU_TZ=UTC TZDIR="$BATS_TEST_TMPDIR" LOGSHURU_TIMESTAMP_FORMAT='%H:%M %z'
	run --separate-stderr invoke_logger library INFO "UTC without zone files"
	[ "$status" -eq 0 ]
	[[ "$output" == '10:30 +0000 | '* ]]
	[ -z "$stderr" ]
}

@test "named timezone validation honors the configured TZDIR" {
	export LOGSHURU_TZ=Asia/Kolkata TZDIR="$BATS_TEST_TMPDIR"
	run --separate-stderr invoke_logger cli INFO "must not be emitted"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[[ "$stderr" == *"Invalid LOGSHURU_TZ:"*Asia/Kolkata* ]]
}

@test "default timezone behavior does not create a TZ variable in the caller" {
	freeze_time
	unset TZ
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		[[ ! ${TZ+x} ]]
		log INFO "system timezone"
		[[ ! ${TZ+x} ]]
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == *"system timezone" ]]
	[ -z "$stderr" ]
}
