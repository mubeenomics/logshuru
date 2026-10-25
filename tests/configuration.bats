#!/usr/bin/env bats

# Child Bash commands expand their own variables; Bats isolates test state.
# shellcheck disable=SC2016,SC2030,SC2031

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
	LEVELS=(TRACE DEBUG PROCESS INFO SUCCESS WARNING ERROR CRITICAL)
}

@test "unset and empty LOG_LEVEL initialize the PROCESS default" {
	run --separate-stderr env -u LOG_LEVEL bash -c 'source "$1" || exit; get_log_level' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ "$output" = PROCESS ]
	[ -z "$stderr" ]

	export LOG_LEVEL=""
	run --separate-stderr bash -c 'source "$1" || exit; get_log_level' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ "$output" = PROCESS ]
	[ -z "$stderr" ]
}

@test "environment levels initialize to uppercase for all supported levels" {
	for level in "${LEVELS[@]}"; do
		export LOG_LEVEL="${level,,}"
		run --separate-stderr bash -c 'source "$1" || exit; get_log_level' bash "$LOGSHURU"
		[ "$status" -eq 0 ]
		[ "$output" = "$level" ]
		[ -z "$stderr" ]
	done
}

@test "lowercase and mixed-case environment thresholds filter in both modes" {
	for LOG_LEVEL in error ErRoR; do
		for mode in cli library; do
			run --separate-stderr invoke_logger "$mode" INFO "must be filtered"
			[ "$status" -eq 0 ]
			[ -z "$output" ]
			[ -z "$stderr" ]
			run --separate-stderr invoke_logger "$mode" ERROR "visible error"
			[ "$status" -eq 0 ]
			[[ "$output" == *"visible error"* ]]
			[ -z "$stderr" ]
		done
	done
}

@test "invalid environment configuration fails initialization in both modes" {
	for LOG_LEVEL in INVALID ' ERROR ' ' ' 'invalid\c%s'; do
		for mode in cli library; do
			run --separate-stderr invoke_logger "$mode" INFO "must not be emitted"
			[ "$status" -eq 1 ]
			[ -z "$output" ]
			[[ "$stderr" == *"Invalid LOG_LEVEL:"*"$LOG_LEVEL"* ]]
			[[ "$stderr" == *"Valid levels:"* ]]
		done
	done
}

@test "invalid configuration returns from source without exiting the caller" {
	export LOG_LEVEL=INVALID
	run --separate-stderr bash -c '
		if source "$1"; then
			exit 99
		else
			result=$?
		fi
		printf "caller continued: %s\n" "$result"
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ "$output" = 'caller continued: 1' ]
	[[ "$stderr" == *"Invalid LOG_LEVEL:"*INVALID* ]]
}

@test "setter normalizes and exports every supported level" {
	for level in "${LEVELS[@]}"; do
		run --separate-stderr bash -c '
			source "$1" || exit
			set_log_level "$2" >/dev/null || exit
			get_log_level
			bash -c '\''printf "%s\n" "$LOG_LEVEL"'\''
		' bash "$LOGSHURU" "${level,,}"
		[ "$status" -eq 0 ]
		[ "$output" = "$level"$'\n'"$level" ]
		[ -z "$stderr" ]
	done
}

@test "invalid setter inputs return failure with clean diagnostics" {
	for level in INVALID '' ' ERROR ' ' '; do
		run --separate-stderr bash -c '
			source "$1" || exit
			set_log_level "$2"
		' bash "$LOGSHURU" "$level"
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[[ "$stderr" == *"not a valid log level"* ]]
		[[ "$stderr" == *"Valid levels:"* ]]
		[[ "$stderr" != *"bad array subscript"* ]]
	done
}

@test "invalid setter inputs preserve the active and exported level" {
	for level in INVALID ''; do
		run --separate-stderr bash -c '
			source "$1" || exit
			set_log_level ERROR || exit
			if set_log_level "$2"; then exit 99; fi
			[[ "$(get_log_level)" == ERROR && "$LOG_LEVEL" == ERROR ]] || exit 1
			log INFO "must be filtered" || exit
			log ERROR "still active"
		' bash "$LOGSHURU" "$level"
		[ "$status" -eq 0 ]
		[[ "$output" == *"still active"* ]]
		[[ "$output" != *"must be filtered"* ]]
		[[ "$stderr" == *"not a valid log level"* ]]
		[[ "$stderr" != *"bad array subscript"* ]]
	done
}

@test "changing LOG_LEVEL after sourcing requires the setter to update active filtering" {
	run --separate-stderr bash -c '
		source "$1" || exit
		export LOG_LEVEL=ERROR
		[[ "$(get_log_level)" == PROCESS ]] || exit 1
		log INFO "before setter" || exit
		set_log_level "$LOG_LEVEL" || exit
		[[ "$(get_log_level)" == ERROR ]] || exit 1
		log INFO "after setter"
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == *"before setter"* ]]
	[[ "$output" != *"after setter"* ]]
	[ -z "$stderr" ]
}
