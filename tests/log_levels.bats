#!/usr/bin/env bats

# Bats isolates each test; shared variable names do not leak between tests.
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.5.0

# shellcheck source=test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	export LOG_LEVEL=PROCESS
	export LOGSHURU_COLOR=always
	export LOGSHURU_OUTPUT=stdout
	unset LOGSHURU_TIMESTAMP_FORMAT LOGSHURU_TZ
	LEVELS=(TRACE DEBUG PROCESS INFO SUCCESS WARNING ERROR CRITICAL)
}

@test "CLI accepts all eight levels and returns success" {
	export LOG_LEVEL=TRACE
	for level in "${LEVELS[@]}"; do
		run --separate-stderr invoke_logger cli "$level" "message for $level"
		[ "$status" -eq 0 ]
		[[ "$output" == *"message for $level"* ]]
		[ -z "$stderr" ]
	done
}

@test "library accepts all eight levels and returns success" {
	export LOG_LEVEL=TRACE
	for level in "${LEVELS[@]}"; do
		run --separate-stderr invoke_logger library "$level" "message for $level"
		[ "$status" -eq 0 ]
		[[ "$output" == *"message for $level"* ]]
		[ -z "$stderr" ]
	done
}

@test "invalid CLI levels fail at every threshold with diagnostics only on stderr" {
	for LOG_LEVEL in "${LEVELS[@]}"; do
		run --separate-stderr invoke_logger cli INVALID "must not be emitted"
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Invalid log level:"*INVALID* ]]
		[[ "$stderr" == *"Valid levels:"* ]]
	done
}

@test "invalid library levels fail at every threshold with diagnostics only on stderr" {
	for LOG_LEVEL in "${LEVELS[@]}"; do
		run --separate-stderr invoke_logger library INVALID "must not be emitted"
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Invalid log level:"*INVALID* ]]
		[[ "$stderr" == *"Valid levels:"* ]]
	done
}

@test "valid messages below the threshold are silently successful in both modes" {
	export LOG_LEVEL=ERROR
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "must not be emitted"
		[ "$status" -eq 0 ]
		[ -z "$output" ]
		[ -z "$stderr" ]
	done
}

@test "lowercase message levels remain supported in both modes" {
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" info "lowercase message"
		[ "$status" -eq 0 ]
		[[ "$output" == *INFO*"lowercase message"* ]]
		[ -z "$stderr" ]
	done
}

@test "empty levels fail cleanly before filtering in both modes" {
	export LOG_LEVEL=ERROR
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" "" "must not be emitted"
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Invalid log level:"* ]]
		[[ "$stderr" != *"bad array subscript"* ]]
	done
}

assert_threshold_matrix() {
	local mode="$1" threshold level
	# Explicit expected sets keep the test independent of the implementation's
	# numeric severity table and comparison logic.
	local visible_levels=(
		'TRACE DEBUG PROCESS INFO SUCCESS WARNING ERROR CRITICAL'
		'DEBUG PROCESS INFO SUCCESS WARNING ERROR CRITICAL'
		'PROCESS INFO SUCCESS WARNING ERROR CRITICAL'
		'INFO SUCCESS WARNING ERROR CRITICAL'
		'SUCCESS WARNING ERROR CRITICAL'
		'WARNING ERROR CRITICAL'
		'ERROR CRITICAL'
		'CRITICAL'
	)
	for threshold in "${!LEVELS[@]}"; do
		export LOG_LEVEL="${LEVELS[$threshold]}"
		for level in "${LEVELS[@]}"; do
			printf 'mode=%s threshold=%s message_level=%s\n' "$mode" "$LOG_LEVEL" "$level"
			run --separate-stderr invoke_logger "$mode" "$level" "matrix message $level"
			[ "$status" -eq 0 ]
			[ -z "$stderr" ]
			if [[ " ${visible_levels[$threshold]} " == *" $level "* ]]; then
				[[ "$output" == *"matrix message $level"$'\e[0m' ]]
			else
				[ -z "$output" ]
			fi
		done
	done
}

@test "CLI filtering matches every level and threshold combination" {
	assert_threshold_matrix cli
}

@test "library filtering matches every level and threshold combination" {
	assert_threshold_matrix library
}
