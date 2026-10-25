#!/usr/bin/env bats

# Variables in child Bash command strings expand in that child, not in Bats.
# shellcheck disable=SC2016
# Bats runs each test in an isolated subshell.
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.5.0

setup() {
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	export LOG_LEVEL=PROCESS LOGSHURU_COLOR=never LOGSHURU_OUTPUT=stdout
	export LOGSHURU_FORMAT=text
	unset LOGSHURU_TIMESTAMP_FORMAT LOGSHURU_TZ LOGSHURU_FILE
}

@test "function-local sourcing leaves usable global state under strict mode" {
	for format in text json; do
		export LOGSHURU_FORMAT="$format"
		run --separate-stderr bash -euo pipefail -c '
			load() { source "$1"; }
			load "$1"
			[[ "$(get_log_level)" == PROCESS ]]
			log TRACE filtered
			set_log_level DEBUG
			[[ "$(get_log_level)" == DEBUG && "$LOG_LEVEL" == DEBUG ]]
			log DEBUG "after loader"
		' bash "$LOGSHURU"
		[ "$status" -eq 0 ]
		[ -z "$stderr" ]
		[[ "$output" != *filtered* ]]
		[[ "$output" == *"after loader"* ]]
		if [[ "$format" == json ]]; then
			printf '%s\n' "$output" | jq -se '
				length == 2 and .[0].level == "INFO" and
				.[1].level == "DEBUG" and .[1].message == "after loader"
			' >/dev/null
		else
			[[ "$output" == *" | DEBUG    | "*" - after loader" ]]
		fi
	done
}

@test "sourcing preserves caller variables and generic helper functions" {
	run --separate-stderr bash -euo pipefail -c '
		VERSION=caller-version
		DEFAULT_LOG_LEVEL=caller-default
		current_log_level=caller-level
		COLORS=(red green)
		LOG_LEVELS=(caller levels)
		logshuru_format=caller-format
		main() { printf main; }
		show_help() { printf show_help; }
		should_log() { printf should_log; }
		is_sourced() { printf is_sourced; }
		logshuru_timestamp() { printf caller-timestamp; }
		before=$(declare -p VERSION DEFAULT_LOG_LEVEL current_log_level COLORS LOG_LEVELS logshuru_format)
		functions_before=$(declare -f main show_help should_log is_sourced logshuru_timestamp)
		source "$1"
		[[ "$before" == "$(declare -p VERSION DEFAULT_LOG_LEVEL current_log_level COLORS LOG_LEVELS logshuru_format)" ]]
		[[ "$functions_before" == "$(declare -f main show_help should_log is_sourced logshuru_timestamp)" ]]
		log INFO preserved
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[[ "$output" == *" - preserved" ]]
}

@test "message joins use spaces and preserve caller IFS in text and JSON modes" {
	for format in text json; do
		export LOGSHURU_FORMAT="$format"
		for separator in ',' '' $' \t\n'; do
			run --separate-stderr bash -euo pipefail -c '
				source "$1"
				IFS=$2
				log INFO first "" "second part" third
				[[ "$IFS" == "$2" ]]
			' bash "$LOGSHURU" "$separator"
			[ "$status" -eq 0 ]
			[ -z "$stderr" ]
			if [[ "$format" == json ]]; then
				printf '%s\n' "$output" | jq -e '.message == "first  second part third"' >/dev/null
			else
				[[ "$output" == *" - first  second part third" ]]
			fi
		done
	done
}

@test "valid-level diagnostics always list severity order regardless of IFS" {
	local expected='Valid levels: TRACE DEBUG PROCESS INFO SUCCESS WARNING ERROR CRITICAL'
	for entry in environment log setter; do
		run --separate-stderr bash -euo pipefail -c '
			IFS=,
			if [[ "$2" == environment ]]; then LOG_LEVEL=invalid; fi
			source "$1"
			case "$2" in
			log) log invalid message ;;
			setter) set_log_level invalid ;;
			esac
		' bash "$LOGSHURU" "$entry"
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[[ "$stderr" == *"$expected" ]]
	done
}

@test "version uses executable basename and the release version" {
	run --separate-stderr bash "$LOGSHURU" --version
	[ "$status" -eq 0 ]
	[ "$output" = 'logshuru.sh v2.0.0' ]
	[ -z "$stderr" ]
}

@test "logging and CLI metadata no longer invoke basename" {
	run --separate-stderr bash -euo pipefail -c '
		basename() { printf "unexpected basename call\n" >&2; return 99; }
		export -f basename
		source "$1"
		log INFO "without basename"
		bash "$1" --help
		bash "$1" --version
		if bash "$1"; then exit 99; fi
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == *"without basename"* ]]
	[[ "$stderr" != *"unexpected basename call"* ]]
	[[ "$stderr" == *"Usage: logshuru.sh"* ]]
}
