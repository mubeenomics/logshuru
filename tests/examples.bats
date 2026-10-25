#!/usr/bin/env bats

# Child command strings expand in the child shell, not in Bats.
# shellcheck disable=SC2016
# Bats runs each test in an isolated subshell.
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.5.0

setup() {
	EXAMPLE="$BATS_TEST_DIRNAME/../examples/run_command.sh"
	FIXTURE="$BATS_TEST_DIRNAME/fixtures/example_command.bash"
	export LOG_LEVEL=PROCESS LOGSHURU_COLOR=never LOGSHURU_FORMAT=text
	unset LOGSHURU_OUTPUT LOGSHURU_FILE LOGSHURU_TIMESTAMP_FORMAT LOGSHURU_TZ
}

@test "example defaults lifecycle logs to stderr and preserves command streams" {
	run --separate-stderr bash "$EXAMPLE" -- bash "$FIXTURE" streams 0
	[ "$status" -eq 0 ]
	[ "$output" = 'application data' ]
	[[ "$stderr" == *"Command started"*$'\ntool diagnostic\n'*"Command completed exit=0"* ]]
	[[ "$stderr" != *"Runner initialized"* ]]
	local timing='elapsed=[0-9]+s'
	[[ "$stderr" =~ $timing ]]
}

@test "example preserves a failed command status and its diagnostics" {
	run --separate-stderr bash "$EXAMPLE" -- bash "$FIXTURE" streams 23
	[ "$status" -eq 23 ]
	[ "$output" = 'application data' ]
	[[ "$stderr" == *"tool diagnostic"*"Command failed exit=23"* ]]
	[[ "$stderr" != *"Command completed"* ]]
}

@test "example forwards exact arguments without evaluation or logging their values" {
	local args=('with spaces' '' '*' '--leading-option' 'secret=do-not-log' $'line\nbreak' '$(touch injected)' '; exit 99')
	cp "$FIXTURE" "$BATS_TEST_TMPDIR/command with spaces.bash"
	run --separate-stderr bash -euo pipefail -c '
		example=$1
		fixture=$2
		actual=$3
		expected=$4
		shift 4
		cd "${actual%/*}"
		printf "%s\0" "$@" > "$expected"
		bash "$example" -- bash "$fixture" arguments "$@" > "$actual"
		cmp "$actual" "$expected"
	' bash "$EXAMPLE" "$BATS_TEST_TMPDIR/command with spaces.bash" "$BATS_TEST_TMPDIR/actual" "$BATS_TEST_TMPDIR/expected" "${args[@]}"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[[ "$stderr" == *"Command completed exit=0"* ]]
	[[ "$stderr" != *"do-not-log"* && "$stderr" != *"injected"* ]]
}

@test "example finds the library while preserving a different command working directory" {
	run --separate-stderr bash -euo pipefail -c '
		cd "$3"
		bash "$1" -- bash "$2" directory
	' bash "$EXAMPLE" "$FIXTURE" "$BATS_TEST_TMPDIR"
	[ "$status" -eq 0 ]
	[ "$output" = "$BATS_TEST_TMPDIR" ]
}

@test "example can run by its bare filename from the examples directory" {
	run --separate-stderr bash -euo pipefail -c '
		cd "${1%/*}"
		bash run_command.sh -- printf "%s" ok
	' bash "$EXAMPLE"
	[ "$status" -eq 0 ]
	[ "$output" = ok ]
}

@test "example requires a separator and command and reports missing executables" {
	local args
	for args in missing separator command; do
		case "$args" in
		missing) run --separate-stderr bash "$EXAMPLE" ;;
		separator) run --separate-stderr bash "$EXAMPLE" -- ;;
		command) run --separate-stderr bash "$EXAMPLE" printf ;;
		esac
		[ "$status" -eq 2 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Usage:"* ]]
	done
	run -127 --separate-stderr bash "$EXAMPLE" -- "$BATS_TEST_TMPDIR/no-such-command"
	[ "$status" -eq 127 ]
	[[ "$stderr" == *"Command failed exit=127"* ]]
}

@test "example preserves stdin and isolates builtins that exit the command shell" {
	run --separate-stderr bash -euo pipefail -c '
		printf "%s\n" "piped input" | bash "$1" -- cat
	' bash "$EXAMPLE"
	[ "$status" -eq 0 ]
	[ "$output" = 'piped input' ]
	run --separate-stderr bash "$EXAMPLE" -- exit 29
	[ "$status" -eq 29 ]
	[[ "$stderr" == *"Command failed exit=29"* ]]
}

@test "example keeps command success and failure statuses despite lifecycle write failures" {
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/missing-parent/events.log"
	local code
	for code in 0 23; do
		run --separate-stderr bash "$EXAMPLE" -- bash "$FIXTURE" streams "$code"
		[ "$status" -eq "$code" ]
		[ "$output" = 'application data' ]
		[[ "$stderr" == *"Failed to append log file"* ]]
		[[ "$stderr" == *"tool diagnostic"* ]]
	done
}

@test "example rejects invalid logger initialization before executing the command" {
	export LOG_LEVEL=invalid
	run --separate-stderr bash "$EXAMPLE" -- bash "$FIXTURE" streams 0
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[[ "$stderr" == *"Invalid LOG_LEVEL"* ]]
	[[ "$stderr" != *"tool diagnostic"* ]]
}

@test "example accepts DEBUG JSON and explicit stream overrides" {
	export LOG_LEVEL=DEBUG LOGSHURU_FORMAT=json LOGSHURU_OUTPUT=stdout
	run --separate-stderr bash "$EXAMPLE" -- bash "$FIXTURE" streams 0
	[ "$status" -eq 0 ]
	[ "$stderr" = 'tool diagnostic' ]
	[ "${#lines[@]}" -eq 4 ]
	[ "${lines[2]}" = 'application data' ]
	printf '%s\n' "${lines[0]}" "${lines[1]}" "${lines[3]}" | jq -se '
		map(.level) == ["DEBUG", "INFO", "SUCCESS"] and
		all(.[]; .file == "run_command.sh" and .function == "main" and .line > 0)
	' >/dev/null
}
