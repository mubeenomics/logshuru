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
	export LOGSHURU_FORMAT=text
}

@test "strict-mode library initialization supports unset and empty configuration" {
	for configuration in unset empty; do
		run --separate-stderr bash -euo pipefail -c '
			if [[ "$2" == unset ]]; then unset LOG_LEVEL; else export LOG_LEVEL=""; fi
			source "$1"
			[[ "$(get_log_level)" == PROCESS ]]
			log INFO "initialized"
		' bash "$LOGSHURU" "$configuration"
		[ "$status" -eq 0 ]
		[[ "$output" == *"initialized"* ]]
		[ -z "$stderr" ]
	done
}

@test "sourcing and logging preserve the caller's strict shell options" {
	run --separate-stderr bash -euo pipefail -c '
		before=$-
		source "$1"
		log DEBUG "filtered message"
		set_log_level ERROR
		[[ "$-" == "$before" ]]
		[[ -o errexit && -o nounset && -o pipefail ]]
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
}

@test "strict-mode workflow continues after filtered and high-severity messages" {
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		set_log_level debug
		log TRACE "must be filtered"
		log DEBUG "debug details"
		set_log_level ERROR
		[[ "$(get_log_level)" == ERROR ]]
		log INFO "also filtered"
		log ERROR "error event"
		log CRITICAL "critical event"
		printf "workflow completed\n"
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == *"debug details"*"error event"*"critical event"*"workflow completed" ]]
	[[ "$output" != *"must be filtered"* ]]
	[[ "$output" != *"also filtered"* ]]
	[ -z "$stderr" ]
}

@test "strict-mode CLI callers continue after valid emitted and filtered messages" {
	run --separate-stderr bash -euo pipefail -c '
		export LOG_LEVEL=error
		bash -euo pipefail "$1" INFO "must be filtered"
		bash -euo pipefail "$1" ERROR "CLI error event"
		printf "CLI caller continued\n"
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == *"CLI error event"*"CLI caller continued" ]]
	[[ "$output" != *"must be filtered"* ]]
	[ -z "$stderr" ]
}

@test "strict-mode callers can explicitly handle invalid logging and setter calls" {
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		if log INVALID message; then exit 99; fi
		if log INFO; then exit 99; fi
		if set_log_level INVALID; then exit 99; fi
		if set_log_level; then exit 99; fi
		[[ "$(get_log_level)" == PROCESS ]]
		log INFO "recovered"
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == *"recovered"* ]]
	[[ "$stderr" == *"Invalid log level:"* ]]
	[[ "$stderr" == *"Usage: log"* ]]
	[[ "$stderr" == *"not a valid log level"* ]]
	[[ "$stderr" == *"Usage: set_log_level"* ]]
}

@test "unhandled invalid calls terminate strict-mode callers" {
	for entry in log set_log_level; do
		run --separate-stderr bash -euo pipefail -c '
			source "$1"
			if [[ "$2" == log ]]; then log INVALID message; else set_log_level INVALID; fi
			printf "must not continue\n"
		' bash "$LOGSHURU" "$entry"
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[ -n "$stderr" ]
	done
}

@test "invalid initialization can be handled or left to terminate a strict-mode caller" {
	export LOG_LEVEL=INVALID
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		printf "must not continue\n"
	' bash "$LOGSHURU"
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[[ "$stderr" == *"Invalid LOG_LEVEL:"* ]]

	run --separate-stderr bash -euo pipefail -c '
		if source "$1"; then exit 99; fi
		printf "initialization failure handled\n"
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ "$output" = 'initialization failure handled' ]
	[[ "$stderr" == *"Invalid LOG_LEVEL:"* ]]
}

@test "logging does not mask earlier pipeline failures with pipefail enabled" {
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		false | log INFO "pipeline log"
		printf "must not continue\n"
	' bash "$LOGSHURU"
	[ "$status" -eq 1 ]
	[[ "$output" == *"pipeline log"* ]]
	[[ "$output" != *"must not continue"* ]]
	[ -z "$stderr" ]
}

@test "unhandled output failure terminates strict-mode logging" {
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		log INFO "cannot write" >&-
		printf "must not continue\n"
	' bash "$LOGSHURU"
	[ "$status" -ne 0 ]
	[ -z "$output" ]
	[ -n "$stderr" ]
}

@test "handled output failures return nonzero from log and setter" {
	for entry in log set_log_level; do
		run --separate-stderr bash -euo pipefail -c '
			source "$1"
			if [[ "$2" == log ]]; then
				if log INFO "cannot write" >&-; then exit 99; fi
			else
				if set_log_level DEBUG >&-; then exit 99; fi
				[[ "$(get_log_level)" == DEBUG && "$LOG_LEVEL" == DEBUG ]]
			fi
			printf "write failure handled\n"
		' bash "$LOGSHURU" "$entry"
		[ "$status" -eq 0 ]
		[ "$output" = 'write failure handled' ]
		[ -n "$stderr" ]
	done
}
