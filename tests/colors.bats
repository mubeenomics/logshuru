#!/usr/bin/env bats

# Child Bash command strings expand their own variables, not Bats variables.
# shellcheck disable=SC2016,SC2030,SC2031

bats_require_minimum_version 1.5.0

# shellcheck source=test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	export LOG_LEVEL=PROCESS TERM=xterm
	export LOGSHURU_OUTPUT=stdout
	unset LOGSHURU_TIMESTAMP_FORMAT LOGSHURU_TZ
	unset LOGSHURU_FILE
	unset LOGSHURU_COLOR NO_COLOR
}

assert_plain_message() {
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[[ "$output" == *"color message"* ]]
	[[ "$output" != *$'\e['* ]]
}

require_terminal_tool() {
	command -v script >/dev/null || skip "terminal tests require util-linux script"
}

invoke_on_terminal() {
	local mode="$1" command
	if [[ "$mode" == cli ]]; then
		printf -v command 'bash %q INFO %q' "$LOGSHURU" 'color message'
	else
		printf -v command 'bash -euo pipefail -c %q bash %q' \
			'source "$1"; log INFO "color message"' "$LOGSHURU"
	fi
	script -q -e -c "$command" /dev/null
}

@test "unset and empty color configuration default to plain redirected output" {
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "color message"
		assert_plain_message
		export LOGSHURU_COLOR=""
		run --separate-stderr invoke_logger "$mode" INFO "color message"
		assert_plain_message
		unset LOGSHURU_COLOR
	done
}

@test "auto mode disables colors for redirected output in both modes" {
	export LOGSHURU_COLOR=auto
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "color message"
		assert_plain_message
	done
}

@test "always forces colors despite redirection NO_COLOR and TERM=dumb" {
	export LOGSHURU_COLOR=AlWaYs NO_COLOR=1 TERM=dumb
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "color message"
		[ "$status" -eq 0 ]
		[ -z "$stderr" ]
		[[ "$output" == *$'\e[1;37mcolor message\e[0m' ]]
	done
}

@test "never disables logger colors in both modes" {
	export LOGSHURU_COLOR=NeVeR
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "color message"
		assert_plain_message
	done
}

@test "auto mode emits colors to a terminal in both modes" {
	require_terminal_tool
	export LOGSHURU_COLOR=auto
	for mode in cli library; do
		run --separate-stderr invoke_on_terminal "$mode"
		[ "$status" -eq 0 ]
		[ -z "$stderr" ]
		[[ "$output" == *$'\e[1;37mcolor message\e[0m'* ]]
	done
}

@test "NO_COLOR disables automatic terminal colors when nonempty including zero" {
	require_terminal_tool
	export LOGSHURU_COLOR=auto
	for NO_COLOR in 1 0; do
		export NO_COLOR
		run --separate-stderr invoke_on_terminal cli
		assert_plain_message
	done
}

@test "empty NO_COLOR does not disable automatic terminal colors" {
	require_terminal_tool
	export LOGSHURU_COLOR=auto NO_COLOR=""
	run --separate-stderr invoke_on_terminal cli
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[[ "$output" == *$'\e[1;37mcolor message\e[0m'* ]]
}

@test "TERM=dumb disables automatic terminal colors" {
	require_terminal_tool
	export LOGSHURU_COLOR=auto TERM=dumb
	run --separate-stderr invoke_on_terminal cli
	assert_plain_message
}

@test "never disables colors even on a terminal" {
	require_terminal_tool
	export LOGSHURU_COLOR=never
	run --separate-stderr invoke_on_terminal library
	assert_plain_message
}

@test "auto checks the log destination at call time rather than source time" {
	require_terminal_tool
	export LOGSHURU_COLOR=auto
	local command
	printf -v command 'bash -euo pipefail -c %q bash %q %q' \
		'source "$1"; log INFO "color message" >"$2"; printf "%s" "$(<"$2")"' \
		"$LOGSHURU" "$BATS_TEST_TMPDIR/redirected.log"
	run --separate-stderr script -q -e -c "$command" /dev/null
	assert_plain_message
}

@test "never removes logger colors from help and invalid-call diagnostics" {
	export LOGSHURU_COLOR=never
	run --separate-stderr bash "$LOGSHURU" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage:"* ]]
	[[ "$output" != *$'\e['* ]]
	[ -z "$stderr" ]
	for level in INVALID ''; do
		run --separate-stderr invoke_logger library "$level" message
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Invalid log level:"* ]]
		[[ "$stderr" != *$'\e['* ]]
	done
	run --separate-stderr bash "$LOGSHURU"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[[ "$stderr" == *"Usage:"* ]]
	[[ "$stderr" != *$'\e['* ]]
}

@test "invalid color modes fail initialization without exiting a sourced caller" {
	for LOGSHURU_COLOR in INVALID ' auto '; do
		export LOGSHURU_COLOR
		run --separate-stderr bash "$LOGSHURU" INFO "must not be emitted"
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Invalid LOGSHURU_COLOR:"*"$LOGSHURU_COLOR"* ]]
		run --separate-stderr bash -euo pipefail -c \
			'if source "$1"; then exit 99; fi; printf "caller continued\n"' bash "$LOGSHURU"
		[ "$status" -eq 0 ]
		[ "$output" = 'caller continued' ]
		[[ "$stderr" == *"Invalid LOGSHURU_COLOR:"* ]]
	done
}

@test "auto keeps redirected diagnostics plain and always can force their colors" {
	for LOGSHURU_COLOR in auto always; do
		export LOGSHURU_COLOR
		run --separate-stderr invoke_logger cli INVALID message
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		if [[ "$LOGSHURU_COLOR" == auto ]]; then
			[[ "$stderr" != *$'\e['* ]]
		else
			[[ "$stderr" == *$'\e[1;31mInvalid log level:\e[0m'* ]]
		fi
	done
}

@test "color mode is read when the library is sourced" {
	export LOGSHURU_COLOR=always
	run --separate-stderr bash -euo pipefail -c \
		'source "$1"; export LOGSHURU_COLOR=never; log INFO "color message"' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[[ "$output" == *$'\e[1;37mcolor message\e[0m' ]]
}

@test "auto evaluates stderr independently when stdout is redirected" {
	require_terminal_tool
	export LOGSHURU_COLOR=auto
	local command
	printf -v command 'bash -euo pipefail -c %q bash %q' \
		'source "$1"; log INVALID message >/dev/null' "$LOGSHURU"
	run --separate-stderr script -q -e -c "$command" /dev/null
	[ "$status" -eq 1 ]
	[[ "$output" == *$'\e[1;31mInvalid log level:\e[0m'* ]]
	[ -z "$stderr" ]
}

@test "auto keeps redirected stderr plain even when stdout is a terminal" {
	require_terminal_tool
	export LOGSHURU_COLOR=auto
	local command
	printf -v command 'bash -euo pipefail -c %q bash %q %q' \
		'source "$1"; if log INVALID message 2>"$2"; then exit 99; fi; printf "%s" "$(<"$2")"' \
		"$LOGSHURU" "$BATS_TEST_TMPDIR/diagnostic.log"
	run --separate-stderr script -q -e -c "$command" /dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"Invalid log level:"* ]]
	[[ "$output" != *$'\e['* ]]
	[ -z "$stderr" ]
}
