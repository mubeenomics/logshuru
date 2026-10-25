#!/usr/bin/env bats

# Variables in child Bash command strings expand in that child, not in Bats.
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

setup() {
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	FIXTURE="$BATS_TEST_DIRNAME/fixtures/context.bash"
	export LOG_LEVEL=PROCESS
	export LOGSHURU_COLOR=always
	export LOGSHURU_OUTPUT=stdout
	unset LOGSHURU_TIMESTAMP_FORMAT LOGSHURU_TZ
	unset LOGSHURU_FILE
	export LOGSHURU_FORMAT=text
}

strip_context_colors() {
	plain_output="$output"
	local color
	for color in $'\e[0;32m' $'\e[1;37m' $'\e[0;36m' $'\e[0m'; do
		plain_output=${plain_output//"$color"/}
	done
}

assert_location() {
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	strip_context_colors
	local pattern=' \| ([^:|]+):([^:]+):([0-9]+) - ([^ ]+) line=([0-9]+)$'
	[[ "$plain_output" =~ $pattern ]]
	[ "${BASH_REMATCH[1]}" = "$1" ]
	[ "${BASH_REMATCH[2]}" = "$2" ]
	[ "${BASH_REMATCH[4]}" = "$3" ]
	[ "${BASH_REMATCH[3]}" -gt 0 ]
	[ "${BASH_REMATCH[3]}" -eq "${BASH_REMATCH[5]}" ]
}

@test "top-level sourced calls report the caller file and actual line" {
	run --separate-stderr bash "$FIXTURE" "$LOGSHURU" top-level
	assert_location context.bash main top-level
}

@test "function calls report the function containing the log call" {
	run --separate-stderr bash "$FIXTURE" "$LOGSHURU" function
	assert_location context.bash emit_context function
}

@test "nested functions report the immediate caller rather than its outer function" {
	run --separate-stderr bash "$FIXTURE" "$LOGSHURU" nested
	assert_location context.bash emit_context function
}

@test "parenthesized subshells retain their source file and call line" {
	run --separate-stderr bash "$FIXTURE" "$LOGSHURU" subshell
	assert_location context.bash main subshell
}

@test "functions from another sourced file report their defining file and log line" {
	run --separate-stderr bash "$FIXTURE" "$LOGSHURU" helper "$BATS_TEST_DIRNAME/fixtures/context_helper.bash"
	assert_location context_helper.bash helper_context helper
}

@test "CLI context uses explicit placeholders instead of internal logger locations" {
	run --separate-stderr bash "$LOGSHURU" INFO "direct CLI"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	strip_context_colors
	[[ "$plain_output" == *" | cli:cli:0 - direct CLI" ]]

	run --separate-stderr bash "$FIXTURE" "$LOGSHURU" cli
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	strip_context_colors
	[[ "$plain_output" == *" | cli:cli:0 - CLI from script" ]]
}

@test "sourced command strings mark unavailable source filenames as unknown" {
	run --separate-stderr bash -euo pipefail -c 'source "$1"; log INFO "command line=$LINENO"' bash "$LOGSHURU"
	assert_location unknown main command
}
