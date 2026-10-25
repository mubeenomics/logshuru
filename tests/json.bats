#!/usr/bin/env bats

# Child Bash scripts and jq filters expand their own variables; Bats isolates tests.
# shellcheck disable=SC2016,SC2030,SC2031

bats_require_minimum_version 1.5.0

# shellcheck source=test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
	command -v jq >/dev/null || {
		printf 'JSON tests require jq\n' >&2
		return 1
	}
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	export LOG_LEVEL=TRACE LOGSHURU_FORMAT=json LOGSHURU_COLOR=always LOGSHURU_OUTPUT=stdout
	export LOGSHURU_TIMESTAMP_FORMAT=stamp LOGSHURU_TZ=UTC
	unset LOGSHURU_FILE
}

assert_json_message() {
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ "${#lines[@]}" -eq 1 ]
	jq -e --arg expected "$1" '.message == $expected' <<<"$output" >/dev/null
}

@test "CLI and library emit the documented JSON schema and numeric line" {
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" info "JSON message"
		assert_json_message "JSON message"
		jq -e '
			keys == ["file","function","level","line","message","timestamp"] and
			.timestamp == "stamp" and .level == "INFO" and
			(.file | type) == "string" and (.function | type) == "string" and
			(.line | type) == "number" and .line >= 0
		' <<<"$output" >/dev/null
	done
}

@test "CLI context remains explicit in JSON" {
	run --separate-stderr invoke_logger cli INFO context
	assert_json_message context
	jq -e '.file == "cli" and .function == "cli" and .line == 0' <<<"$output" >/dev/null
}

@test "sourced fixture JSON reports the actual function and call line" {
	run --separate-stderr bash "$BATS_TEST_DIRNAME/fixtures/context.bash" "$LOGSHURU" nested
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	jq -e '.file == "context.bash" and .function == "emit_context" and
		.line == (.message | split("=")[1] | tonumber)' <<<"$output" >/dev/null
}

@test "quotes backslashes format directives and shell metacharacters round trip" {
	local message='"quoted" \path\n %s $HOME $(exit 99) `exit 99` / slash'
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "$message"
		assert_json_message "$message"
	done
}

@test "all representable ASCII control characters round trip on one JSON line" {
	local message="" code character
	for ((code = 1; code < 32; code++)); do
		printf -v character '\\x%02x' "$code"
		printf -v character '%b' "$character"
		message+="$character"
	done
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "$message"
		assert_json_message "$message"
	done
}

@test "Unicode empty multiline and trailing-newline messages round trip" {
	local message
	for message in '' 'αβγ café 中文 ✓ 🧬' $'first\n\nlast\n\n'; do
		run --separate-stderr invoke_logger library INFO "$message"
		assert_json_message "$message"
	done
}

@test "invalid UTF-8 is rejected without emitting a record or creating a file" {
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/events.jsonl"
	local message mode
	for message in $'\x80' $'\xc0\x80' $'\xc2x' $'\xe2\x82' $'\xe0\x80\x80' \
		$'\xed\xa0\x80' $'\xf0\x80\x80\x80' $'\xf4\x90\x80\x80' $'\xff'; do
		for mode in cli library; do
			run --separate-stderr invoke_logger "$mode" INFO "$message"
			[ "$status" -ne 0 ]
			[ -z "$output" ]
			[[ "$stderr" == *"valid UTF-8"* ]]
			[ ! -e "$LOGSHURU_FILE" ]
		done
	done
}

@test "forced logger colors never enter JSON but user escape sequences round trip" {
	local message=$'user \e[31mred\e[0m'
	run --separate-stderr invoke_logger cli ERROR "$message"
	assert_json_message "$message"
	[[ "$output" != *$'\e'* ]]
}

@test "custom timestamp strings are escaped and retain configured precision" {
	export LOGSHURU_TIMESTAMP_FORMAT=$'stamp" \\ line%nsecond'
	run --separate-stderr invoke_logger library INFO timestamp
	assert_json_message timestamp
	jq -e --arg expected $'stamp" \\ line\nsecond' '.timestamp == $expected' <<<"$output" >/dev/null
	unset LOGSHURU_TIMESTAMP_FORMAT
	run --separate-stderr invoke_logger cli INFO default
	assert_json_message default
	jq -e '.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}$")' <<<"$output" >/dev/null
}

@test "all levels route correctly in each output mode with valid JSON" {
	local level mode record
	for LOGSHURU_OUTPUT in stdout stderr split; do
		export LOGSHURU_OUTPUT
		for mode in cli library; do
			for level in TRACE DEBUG PROCESS INFO SUCCESS WARNING ERROR CRITICAL; do
				run --separate-stderr invoke_logger "$mode" "$level" routed
				[ "$status" -eq 0 ]
				if [[ "$LOGSHURU_OUTPUT" == stderr ||
					("$LOGSHURU_OUTPUT" == split && "$level" =~ ^(WARNING|ERROR|CRITICAL)$) ]]; then
					[ -z "$output" ]
					record="$stderr"
				else
					[ -z "$stderr" ]
					record="$output"
				fi
				jq -e --arg level "$level" '.level == $level and .message == "routed"' <<<"$record" >/dev/null
			done
		done
	done
}

@test "file output appends identical JSON objects and preserves existing records" {
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/events.jsonl"
	run --separate-stderr bash -euo pipefail -c '
		bash "$1" INFO first
		bash "$1" ERROR second
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ -f "$LOGSHURU_FILE" ]
	[ "$(<"$LOGSHURU_FILE")" = "$output" ]
	jq -se 'length == 2 and .[0].message == "first" and .[1].message == "second"' "$LOGSHURU_FILE" >/dev/null
}

@test "JSON file writes survive stream failure and file failures retain stream JSON" {
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/events.jsonl"
	run --separate-stderr bash -euo pipefail -c 'source "$1"; log INFO stored >&-' bash "$LOGSHURU"
	[ "$status" -ne 0 ]
	[ -z "$output" ]
	[ -f "$LOGSHURU_FILE" ]
	jq -e '.message == "stored"' "$LOGSHURU_FILE" >/dev/null
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/missing/events.jsonl"
	run --separate-stderr invoke_logger cli INFO streamed
	[ "$status" -ne 0 ]
	jq -e '.message == "streamed"' <<<"$output" >/dev/null
	[[ "$stderr" == *"Failed to append log file:"* ]]
}

@test "filtering skips JSON serialization and file output" {
	export LOG_LEVEL=ERROR LOGSHURU_FILE="$BATS_TEST_TMPDIR/events.jsonl"
	run --separate-stderr invoke_logger library INFO $'\x80'
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
	[ ! -e "$LOGSHURU_FILE" ]
}

@test "unset empty and explicit text format preserve existing text output" {
	unset LOGSHURU_FORMAT
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO text
		[ "$status" -eq 0 ]
		[[ "$output" == *'stamp'*' | '* ]]
		[ -z "$stderr" ]
	done
	for LOGSHURU_FORMAT in '' text; do
		export LOGSHURU_FORMAT
		run --separate-stderr invoke_logger cli INFO text
		[ "$status" -eq 0 ]
		[[ "$output" == *'stamp'*' | '* ]]
		[ -z "$stderr" ]
	done
}

@test "format names accept mixed case and invalid formats reject initialization" {
	export LOGSHURU_FORMAT=JsOn
	run --separate-stderr invoke_logger cli INFO mixed
	assert_json_message mixed
	for LOGSHURU_FORMAT in yaml ' json '; do
		export LOGSHURU_FORMAT
		run --separate-stderr invoke_logger cli INFO invalid
		[ "$status" -eq 1 ]
		[ -z "$output" ]
		[[ "$stderr" == *"Invalid LOGSHURU_FORMAT:"* ]]
		run --separate-stderr bash -euo pipefail -c \
			'if source "$1"; then exit 99; fi; printf "caller continued\n"' bash "$LOGSHURU"
		[ "$status" -eq 0 ]
		[ "$output" = 'caller continued' ]
	done
}

@test "help version getter and invalid-call diagnostics retain their existing interface" {
	export LOGSHURU_COLOR=never
	run --separate-stderr bash "$LOGSHURU" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"Usage:"* ]]
	[ -z "$stderr" ]
	run --separate-stderr bash "$LOGSHURU" --version
	[ "$status" -eq 0 ]
	[[ "$output" == 'logshuru.sh v2.0.0' ]]
	[ -z "$stderr" ]
	run --separate-stderr bash -euo pipefail -c 'source "$1"; get_log_level' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ "$output" = TRACE ]
	[ -z "$stderr" ]
	run --separate-stderr invoke_logger library INVALID message
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[[ "$stderr" == *"Invalid log level:"* ]]
}

@test "format is initialized once and exported settings reach sourced children" {
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		bash -euo pipefail -c '\''source "$1"; log INFO child'\'' bash "$1"
		export LOGSHURU_FORMAT=text
		log INFO parent
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	jq -se 'length == 2 and .[0].message == "child" and .[1].message == "parent"' <<<"$output" >/dev/null
}

@test "valid UTF-8 boundary code points round trip without changing caller locale" {
	local message=$'\xc2\x80\xdf\xbf\xe0\xa0\x80\xed\x9f\xbf\xee\x80\x80\xef\xbf\xbf\xf0\x90\x80\x80\xf4\x8f\xbf\xbf'
	export LC_ALL=C.UTF-8
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		log INFO "$2"
		[[ "$LC_ALL" == C.UTF-8 ]]
	' bash "$LOGSHURU" "$message"
	assert_json_message "$message"
}

@test "source filenames with quotes backslashes and newlines are escaped" {
	local name=$'caller" \\\n.bash'
	cp "$BATS_TEST_DIRNAME/fixtures/context.bash" "$BATS_TEST_TMPDIR/$name"
	run --separate-stderr bash "$BATS_TEST_TMPDIR/$name" "$LOGSHURU" function
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ "${#lines[@]}" -eq 1 ]
	jq -e --arg file "$name" '.file == $file and .function == "emit_context"' <<<"$output" >/dev/null
}

@test "invalid UTF-8 timestamp fields are rejected before either destination is written" {
	export LOGSHURU_TIMESTAMP_FORMAT=$'\x80' LOGSHURU_FILE="$BATS_TEST_TMPDIR/events.jsonl"
	run --separate-stderr invoke_logger library INFO message
	[ "$status" -ne 0 ]
	[ -z "$output" ]
	[[ "$stderr" == *"valid UTF-8"* ]]
	[ ! -e "$LOGSHURU_FILE" ]
}
