#!/usr/bin/env bats

# Child commands expand their own variables; Bats isolates each test's state.
# shellcheck disable=SC2016,SC2030,SC2031

bats_require_minimum_version 1.5.0

# shellcheck source=test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	export LOG_LEVEL=TRACE LOGSHURU_COLOR=never
	unset LOGSHURU_TIMESTAMP_FORMAT LOGSHURU_TZ
	unset LOGSHURU_FILE
	export LOGSHURU_FORMAT=text
	unset LOGSHURU_OUTPUT
}

@test "unset and empty output configuration retain stdout in both modes" {
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" ERROR "default destination"
		[ "$status" -eq 0 ]
		[[ "$output" == *"default destination" ]]
		[ -z "$stderr" ]
		export LOGSHURU_OUTPUT=""
		run --separate-stderr invoke_logger "$mode" ERROR "empty destination"
		[ "$status" -eq 0 ]
		[[ "$output" == *"empty destination" ]]
		[ -z "$stderr" ]
		unset LOGSHURU_OUTPUT
	done
}

@test "every level follows stdout stderr and split routing in both modes" {
	local mode level
	for LOGSHURU_OUTPUT in stdout stderr split; do
		export LOGSHURU_OUTPUT
		for mode in cli library; do
			for level in TRACE DEBUG PROCESS INFO SUCCESS WARNING ERROR CRITICAL; do
				printf 'output_mode=%s invocation=%s level=%s\n' "$LOGSHURU_OUTPUT" "$mode" "$level"
				run --separate-stderr invoke_logger "$mode" "$level" "routed message"
				[ "$status" -eq 0 ]
				if [[ "$LOGSHURU_OUTPUT" == stderr ||
					("$LOGSHURU_OUTPUT" == split && "$level" =~ ^(WARNING|ERROR|CRITICAL)$) ]]; then
					[ -z "$output" ]
					[[ "$stderr" == *"routed message" ]]
				else
					[[ "$output" == *"routed message" ]]
					[ -z "$stderr" ]
				fi
			done
		done
	done
}

@test "output modes accept mixed case" {
	for LOGSHURU_OUTPUT in StDeRr SpLiT; do
		export LOGSHURU_OUTPUT
		run --separate-stderr invoke_logger cli WARNING "mixed case"
		[ "$status" -eq 0 ]
		[ -z "$output" ]
		[[ "$stderr" == *"mixed case" ]]
	done
}

@test "invalid output modes reject CLI and sourced initialization cleanly" {
	for LOGSHURU_OUTPUT in INVALID ' stderr '; do
		export LOGSHURU_OUTPUT
		run --separate-stderr invoke_logger cli INFO "must not be emitted"
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Invalid LOGSHURU_OUTPUT:"*"$LOGSHURU_OUTPUT"* ]]
		run --separate-stderr bash -euo pipefail -c \
			'if source "$1"; then exit 99; fi; printf "caller continued\n"' bash "$LOGSHURU"
		[ "$status" -eq 0 ]
		[ "$output" = 'caller continued' ]
		[[ "$stderr" == *"Invalid LOGSHURU_OUTPUT:"* ]]
	done
}

@test "invalid-call diagnostics always use stderr regardless of routing" {
	for LOGSHURU_OUTPUT in stdout stderr split; do
		export LOGSHURU_OUTPUT
		for mode in cli library; do
			run --separate-stderr invoke_logger "$mode" INVALID message
			[ "$status" -eq 1 ]
			[ -z "$output" ]
			[[ "$stderr" == *"Invalid log level:"* ]]
		done
	done
}

@test "help version and getter remain on stdout in stderr mode" {
	export LOGSHURU_OUTPUT=stderr
	for flag in --help --version; do
		run --separate-stderr bash "$LOGSHURU" "$flag"
		[ "$status" -eq 0 ]
		[ -n "$output" ]
		[ -z "$stderr" ]
	done
	run --separate-stderr bash -euo pipefail -c 'source "$1"; get_log_level' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ "$output" = TRACE ]
	[ -z "$stderr" ]
}

@test "setter notifications follow output routing under strict mode" {
	export LOGSHURU_OUTPUT=stderr
	run --separate-stderr bash -euo pipefail -c \
		'source "$1"; set_log_level DEBUG; get_log_level' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ "$output" = DEBUG ]
	[[ "$stderr" == *"Current log level: DEBUG" ]]
}

invoke_with_closed_descriptor() {
	local invocation="$1" descriptor="$2"
	shift 2
	case "$descriptor" in
	1) invoke_logger "$invocation" "$@" >&- ;;
	2) invoke_logger "$invocation" "$@" 2>&- ;;
	both) invoke_logger "$invocation" "$@" >&- 2>&- ;;
	esac
}

@test "selected-stream write failures return nonzero in both modes" {
	local descriptor mode
	for LOGSHURU_OUTPUT in stdout stderr split; do
		export LOGSHURU_OUTPUT
		descriptor=2
		if [[ "$LOGSHURU_OUTPUT" == stdout ]]; then descriptor=1; fi
		for mode in cli library; do
			run --separate-stderr invoke_with_closed_descriptor "$mode" "$descriptor" WARNING "cannot write"
			[ "$status" -ne 0 ]
			[ -z "$output" ]
		done
	done
}

@test "closing an unused descriptor does not prevent logging" {
	for LOGSHURU_OUTPUT in stdout stderr split; do
		export LOGSHURU_OUTPUT
		if [[ "$LOGSHURU_OUTPUT" == stderr ]]; then
			run --separate-stderr invoke_with_closed_descriptor library 1 INFO "still writable"
			[ "$status" -eq 0 ]
			[ -z "$output" ]
			[[ "$stderr" == *"still writable" ]]
		else
			run --separate-stderr invoke_with_closed_descriptor library 2 INFO "still writable"
			[ "$status" -eq 0 ]
			[[ "$output" == *"still writable" ]]
			[ -z "$stderr" ]
		fi
	done
}

@test "filtered messages require neither descriptor to be writable" {
	export LOG_LEVEL=CRITICAL
	for LOGSHURU_OUTPUT in stdout stderr split; do
		export LOGSHURU_OUTPUT
		for mode in cli library; do
			run --separate-stderr invoke_with_closed_descriptor "$mode" both INFO "filtered message"
			[ "$status" -eq 0 ]
			[ -z "$output" ]
			[ -z "$stderr" ]
		done
	done
}

@test "stderr routing keeps command-substitution data separate from logs" {
	export LOGSHURU_OUTPUT=stderr
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		data=$(log INFO "processing sample"; printf "sample-42")
		[[ "$data" == sample-42 ]]
		printf "%s\n" "$data"
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ "$output" = sample-42 ]
	[[ "$stderr" == *"processing sample" ]]
}

@test "output mode is initialized once and inherited by explicitly sourced children" {
	export LOGSHURU_OUTPUT=stderr
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		bash -euo pipefail -c '\''source "$1"; log INFO "child log"'\'' bash "$1"
		export LOGSHURU_OUTPUT=stdout
		log INFO "parent log"
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[[ "$stderr" == *"child log"*"parent log" ]]
}

@test "automatic colors use selected stderr terminal status in stderr and split modes" {
	command -v script >/dev/null || skip "terminal tests require util-linux script"
	export LOGSHURU_COLOR=auto TERM=xterm
	unset NO_COLOR
	local command
	printf -v command 'bash -euo pipefail -c %q bash %q' \
		'source "$1"; log WARNING "terminal warning" >/dev/null' "$LOGSHURU"
	for LOGSHURU_OUTPUT in stderr split; do
		export LOGSHURU_OUTPUT
		run --separate-stderr script -q -e -c "$command" /dev/null
		[ "$status" -eq 0 ]
		[[ "$output" == *$'\e[1;33mterminal warning\e[0m'* ]]
		[ -z "$stderr" ]
	done
}

@test "automatic colors stay off for redirected stderr even when stdout is a terminal" {
	command -v script >/dev/null || skip "terminal tests require util-linux script"
	export LOGSHURU_OUTPUT=stderr LOGSHURU_COLOR=auto TERM=xterm
	unset NO_COLOR
	local command
	printf -v command 'bash -euo pipefail -c %q bash %q %q' \
		'source "$1"; log WARNING "redirected warning" 2>"$2"; printf "%s" "$(<"$2")"' \
		"$LOGSHURU" "$BATS_TEST_TMPDIR/redirected.log"
	run --separate-stderr script -q -e -c "$command" /dev/null
	[ "$status" -eq 0 ]
	[[ "$output" == *"redirected warning"* ]]
	[[ "$output" != *$'\e['* ]]
	[ -z "$stderr" ]
}
