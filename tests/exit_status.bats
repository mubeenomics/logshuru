#!/usr/bin/env bats

# Variables in child Bash command strings expand in that child, not in Bats.
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

# shellcheck source=test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	export LOG_LEVEL=PROCESS
	export LOGSHURU_COLOR=always
	export LOGSHURU_OUTPUT=stdout
	unset LOGSHURU_TIMESTAMP_FORMAT LOGSHURU_TZ
	unset LOGSHURU_FILE
	export LOGSHURU_FORMAT=text
}

invoke_without_stdout() {
	invoke_logger "$@" >&-
}

@test "CLI and library propagate output failures without relying on errexit" {
	for mode in cli library; do
		run --separate-stderr invoke_without_stdout "$mode" INFO "cannot write"
		[ "$status" -ne 0 ]
		[ -z "$output" ]
		[ -n "$stderr" ]
	done
}

@test "filtered messages need no writable output and still return success" {
	export LOG_LEVEL=ERROR
	for mode in cli library; do
		run --separate-stderr invoke_without_stdout "$mode" INFO "must be filtered"
		[ "$status" -eq 0 ]
		[ -z "$output" ]
		[ -z "$stderr" ]
	done
}

@test "getter returns failure when its result cannot be written" {
	run --separate-stderr bash -c 'source "$1" || exit; get_log_level >&-' bash "$LOGSHURU"
	[ "$status" -ne 0 ]
	[ -z "$output" ]
	[ -n "$stderr" ]
}

@test "help and version return failure when their output cannot be written" {
	for flag in -h --help -v --version; do
		run --separate-stderr bash -c 'bash "$1" "$2" >&-' bash "$LOGSHURU" "$flag"
		[ "$status" -ne 0 ]
		[ -z "$output" ]
		[ -n "$stderr" ]
	done
}
