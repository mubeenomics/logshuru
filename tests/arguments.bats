#!/usr/bin/env bats

# Variables in child Bash command strings expand in that child, not in Bats.
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

setup() {
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	export LOG_LEVEL=PROCESS
	export LOGSHURU_COLOR=always
	export LOGSHURU_OUTPUT=stdout
	unset LOGSHURU_TIMESTAMP_FORMAT LOGSHURU_TZ
	unset LOGSHURU_FILE
}

# The entry is either the CLI or a public library function.
invoke_entrypoint() {
	local entry="$1" shell_mode="$2"
	shift 2
	local options=()
	if [[ "$shell_mode" == nounset ]]; then options=(-u); fi
	if [[ "$entry" == cli ]]; then
		bash "${options[@]}" "$LOGSHURU" "$@"
	else
		bash "${options[@]}" -c 'source "$1" || exit; shift; "$@"' bash "$LOGSHURU" "$entry" "$@"
	fi
}

assert_usage_error() {
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[[ "$stderr" == *"Usage:"* ]]
	[[ "$stderr" != *"unbound variable"* ]]
	[[ "$stderr" != *"bad array subscript"* ]]
}

@test "CLI and log reject missing arguments cleanly, including under nounset" {
	for entry in cli log; do
		for shell_mode in normal nounset; do
			run --separate-stderr invoke_entrypoint "$entry" "$shell_mode"
			assert_usage_error
		done
	done
}

@test "CLI and log reject a missing message even when its level would be filtered" {
	export LOG_LEVEL=CRITICAL
	for entry in cli log; do
		for shell_mode in normal nounset; do
			run --separate-stderr invoke_entrypoint "$entry" "$shell_mode" INFO
			assert_usage_error
		done
	done
}

@test "empty and whitespace levels fail without shell diagnostics under nounset" {
	for entry in cli log; do
		for level in '' ' '; do
			run --separate-stderr invoke_entrypoint "$entry" nounset "$level" message
			[ "$status" -eq 1 ]
			[ -z "$output" ]
			[[ "$stderr" == *"Invalid log level:"* ]]
			[[ "$stderr" != *"unbound variable"* ]]
			[[ "$stderr" != *"bad array subscript"* ]]
		done
	done
}

@test "explicitly empty messages remain valid in both modes under nounset" {
	for entry in cli log; do
		run --separate-stderr invoke_entrypoint "$entry" nounset INFO ''
		[ "$status" -eq 0 ]
		[[ "$output" == *" - "$'\e[1;37m\e[0m' ]]
		[ -z "$stderr" ]
	done
}

@test "multiple message arguments remain joined with spaces under nounset" {
	for entry in cli log; do
		run --separate-stderr invoke_entrypoint "$entry" nounset INFO first 'second part' third
		[ "$status" -eq 0 ]
		[[ "$output" == *"first second part third"$'\e[0m' ]]
		[ -z "$stderr" ]
	done
}

@test "setter rejects missing or extra arguments with usage diagnostics" {
	for shell_mode in normal nounset; do
		run --separate-stderr invoke_entrypoint set_log_level "$shell_mode"
		assert_usage_error
		run --separate-stderr invoke_entrypoint set_log_level "$shell_mode" ERROR extra
		assert_usage_error
	done
}

@test "setter rejects an empty level cleanly under nounset" {
	run --separate-stderr invoke_entrypoint set_log_level nounset ''
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[[ "$stderr" == *"not a valid log level"* ]]
	[[ "$stderr" != *"unbound variable"* ]]
	[[ "$stderr" != *"bad array subscript"* ]]
}

@test "setter argument-count errors preserve active and exported configuration" {
	for count in missing extra; do
		run --separate-stderr bash -u -c '
			source "$1" || exit
			set_log_level ERROR || exit
			if [[ "$2" == missing ]]; then set --; else set -- DEBUG extra; fi
			if set_log_level "$@"; then exit 99; fi
			[[ "$(get_log_level)" == ERROR && "$LOG_LEVEL" == ERROR ]]
		' bash "$LOGSHURU" "$count"
		[ "$status" -eq 0 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Usage:"* ]]
	done
}

@test "help and version flags remain successful with no message under nounset" {
	for flag in -h --help -v --version; do
		run --separate-stderr invoke_entrypoint cli nounset "$flag"
		[ "$status" -eq 0 ]
		[ -n "$output" ]
		[ -z "$stderr" ]
	done
}
