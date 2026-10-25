#!/usr/bin/env bats

# Child commands expand their own variables; Bats isolates test state.
# shellcheck disable=SC2016,SC2030,SC2031

bats_require_minimum_version 1.5.0

# shellcheck source=test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	export LOG_LEVEL=TRACE LOGSHURU_COLOR=never LOGSHURU_OUTPUT=stdout
	export LOGSHURU_TIMESTAMP_FORMAT=stamp LOGSHURU_TZ=UTC
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/events.log"
	export LOGSHURU_FORMAT=text
}

@test "file logging duplicates the same record in CLI and library modes" {
	for mode in cli library; do
		export LOGSHURU_FILE="$BATS_TEST_TMPDIR/$mode.log"
		run --separate-stderr invoke_logger "$mode" INFO "file message"
		[ "$status" -eq 0 ]
		[ -z "$stderr" ]
		[[ "$output" == 'stamp | INFO     | '*"file message" ]]
		[ -f "$LOGSHURU_FILE" ]
		[ "$(<"$LOGSHURU_FILE")" = "$output" ]
	done
}

@test "file logging appends across CLI invocations without truncation" {
	printf 'existing contents\n' >"$LOGSHURU_FILE"
	run --separate-stderr bash -euo pipefail -c '
		bash "$1" INFO first
		bash "$1" ERROR second
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ "$(<"$LOGSHURU_FILE")" = 'existing contents'$'\n'"$output" ]
}

@test "all stream modes keep routing while duplicating records to the file" {
	for LOGSHURU_OUTPUT in stdout stderr split; do
		export LOGSHURU_OUTPUT
		for level in INFO WARNING ERROR; do
			export LOGSHURU_FILE="$BATS_TEST_TMPDIR/$LOGSHURU_OUTPUT-$level.log"
			run --separate-stderr invoke_logger library "$level" "routed file message"
			[ "$status" -eq 0 ]
			[ -f "$LOGSHURU_FILE" ]
			if [[ "$LOGSHURU_OUTPUT" == stderr || ("$LOGSHURU_OUTPUT" == split && "$level" != INFO) ]]; then
				[ -z "$output" ]
				[ "$(<"$LOGSHURU_FILE")" = "$stderr" ]
			else
				[ -z "$stderr" ]
				[ "$(<"$LOGSHURU_FILE")" = "$output" ]
			fi
		done
	done
}

@test "file copies omit logger colors even when stream colors are forced" {
	export LOGSHURU_COLOR=always
	run --separate-stderr invoke_logger cli INFO "colored stream"
	[ "$status" -eq 0 ]
	[[ "$output" == *$'\e[1;37mcolored stream\e[0m' ]]
	[ -z "$stderr" ]
	[ -f "$LOGSHURU_FILE" ]
	local contents
	contents=$(<"$LOGSHURU_FILE")
	[[ "$contents" == 'stamp | INFO     | cli:cli:0 - colored stream' ]]
	[[ "$contents" != *$'\e['* ]]
}

@test "file copies preserve multiline literal and user-supplied ANSI message content" {
	local message=$'literal \\n %s "quoted"\n\tαβγ \e[31muser color\e[0m'
	run --separate-stderr invoke_logger library INFO "$message"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ -f "$LOGSHURU_FILE" ]
	[ "$(<"$LOGSHURU_FILE")" = "$output" ]
	[[ "$output" == *"$message" ]]
}

@test "file paths preserve spaces and shell metacharacters literally" {
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/events [sample] \$literal.log"
	run --separate-stderr invoke_logger cli INFO "literal path"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ -f "$LOGSHURU_FILE" ]
	[ "$(<"$LOGSHURU_FILE")" = "$output" ]
}

@test "filtered messages do not create or open a configured file" {
	export LOG_LEVEL=ERROR LOGSHURU_FILE="$BATS_TEST_TMPDIR/missing/events.log"
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO filtered
		[ "$status" -eq 0 ]
		[ -z "$output" ]
		[ -z "$stderr" ]
		[ ! -e "$LOGSHURU_FILE" ]
	done
	[ ! -d "$BATS_TEST_TMPDIR/missing" ]
}

@test "sourcing help version getter and invalid calls do not create a log file" {
	run --separate-stderr bash -euo pipefail -c 'source "$1"; get_log_level' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ "$output" = TRACE ]
	[ -z "$stderr" ]
	[ ! -e "$LOGSHURU_FILE" ]
	for flag in --help --version; do
		run --separate-stderr bash "$LOGSHURU" "$flag"
		[ "$status" -eq 0 ]
		[ -z "$stderr" ]
		[ ! -e "$LOGSHURU_FILE" ]
	done
	run --separate-stderr invoke_logger cli INVALID message
	[ "$status" -eq 1 ]
	[ -z "$output" ]
	[ ! -e "$LOGSHURU_FILE" ]
}

@test "missing parent directories report failure without suppressing stream output" {
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/missing/events.log"
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "stream survives"
		[ "$status" -ne 0 ]
		[[ "$output" == *"stream survives" ]]
		[[ "$stderr" == *"Failed to append log file:"*"$LOGSHURU_FILE"* ]]
		[ ! -e "$LOGSHURU_FILE" ]
	done
	[ ! -d "$BATS_TEST_TMPDIR/missing" ]
}

@test "directories and FIFOs are rejected rather than used as file sinks" {
	mkfifo "$BATS_TEST_TMPDIR/events.pipe"
	for LOGSHURU_FILE in "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/events.pipe"; do
		export LOGSHURU_FILE
		run --separate-stderr invoke_logger cli INFO "stream survives"
		[ "$status" -ne 0 ]
		[[ "$output" == *"stream survives" ]]
		[[ "$stderr" == *"Log file is not a regular file:"*"$LOGSHURU_FILE"* ]]
	done
}

@test "unwritable regular files report failure and preserve existing contents" {
	printf 'existing contents\n' >"$LOGSHURU_FILE"
	chmod a-w "$LOGSHURU_FILE"
	[[ ! -w "$LOGSHURU_FILE" ]] || skip "current user can write despite file permissions"
	run --separate-stderr invoke_logger library INFO "stream survives"
	[ "$status" -ne 0 ]
	[[ "$output" == *"stream survives" ]]
	[[ "$stderr" == *"Failed to append log file:"* ]]
	[ "$(<"$LOGSHURU_FILE")" = 'existing contents' ]
}

invoke_with_closed_stdout() {
	invoke_logger "$@" >&-
}

@test "file append is still attempted when the selected stream fails" {
	for mode in cli library; do
		export LOGSHURU_FILE="$BATS_TEST_TMPDIR/$mode.log"
		run --separate-stderr invoke_with_closed_stdout "$mode" INFO "file survives"
		[ "$status" -ne 0 ]
		[ -z "$output" ]
		[ -f "$LOGSHURU_FILE" ]
		[[ "$(<"$LOGSHURU_FILE")" == *"file survives" ]]
	done
}

@test "file failures terminate an unhandled strict-mode call after stream emission" {
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/missing/events.log"
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		log INFO "stream survives"
		printf "must not continue\n"
	' bash "$LOGSHURU"
	[ "$status" -ne 0 ]
	[[ "$output" == *"stream survives" ]]
	[[ "$output" != *"must not continue"* ]]
	[[ "$stderr" == *"Failed to append log file:"* ]]
}

@test "handled setter calls propagate file failures while retaining the new level" {
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/missing/events.log"
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		if set_log_level DEBUG; then exit 99; fi
		[[ "$(get_log_level)" == DEBUG ]]
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == *"Current log level: DEBUG" ]]
	[[ "$stderr" == *"Failed to append log file:"* ]]
}

@test "configured file is captured at source time and inherited by child initialization" {
	run --separate-stderr bash -euo pipefail -c '
		source "$1"
		bash -euo pipefail -c '\''source "$1"; log INFO "child record"'\'' bash "$1"
		export LOGSHURU_FILE="$2"
		log INFO "parent record"
	' bash "$LOGSHURU" "$BATS_TEST_TMPDIR/other.log"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ -f "$LOGSHURU_FILE" ]
	[ "$(<"$LOGSHURU_FILE")" = "$output" ]
	[ ! -e "$BATS_TEST_TMPDIR/other.log" ]
}

@test "relative file paths stay anchored to the initialization directory" {
	mkdir "$BATS_TEST_TMPDIR/start" "$BATS_TEST_TMPDIR/later"
	export LOGSHURU_FILE=events.log
	run --separate-stderr bash -euo pipefail -c '
		cd "$2"
		source "$1"
		cd "$3"
		log INFO "anchored record"
	' bash "$LOGSHURU" "$BATS_TEST_TMPDIR/start" "$BATS_TEST_TMPDIR/later"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ -f "$BATS_TEST_TMPDIR/start/events.log" ]
	[ "$(<"$BATS_TEST_TMPDIR/start/events.log")" = "$output" ]
	[ ! -e "$BATS_TEST_TMPDIR/later/events.log" ]
}

@test "unset and empty file configuration disable file logging" {
	unset LOGSHURU_FILE
	run --separate-stderr invoke_logger cli INFO "no file"
	[ "$status" -eq 0 ]
	[[ "$output" == *"no file" ]]
	[ -z "$stderr" ]
	export LOGSHURU_FILE=""
	run --separate-stderr invoke_logger library INFO "empty file setting"
	[ "$status" -eq 0 ]
	[[ "$output" == *"empty file setting" ]]
	[ -z "$stderr" ]
}

@test "timestamp failures do not create a file or emit a record" {
	# Exported stub is invoked indirectly by child Bash processes.
	# shellcheck disable=SC2317
	date() { return 23; }
	export -f date
	run --separate-stderr invoke_logger cli INFO "must not be emitted"
	[ "$status" -ne 0 ]
	[ -z "$output" ]
	[[ "$stderr" == *"Failed to generate log timestamp"* ]]
	[ ! -e "$LOGSHURU_FILE" ]
}

@test "file copies preserve trailing message newlines and add a record terminator" {
	local message=$'first line\n\n' contents
	run --separate-stderr invoke_logger library INFO "$message"
	[ "$status" -eq 0 ]
	[ -z "$stderr" ]
	[ -f "$LOGSHURU_FILE" ]
	# Unlike command substitution, read retains the complete trailing newlines.
	IFS= read -r -d '' contents <"$LOGSHURU_FILE" || true
	[[ "$contents" == *" - $message"$'\n' ]]
}

@test "file failure diagnostics coexist with records routed to stderr" {
	export LOGSHURU_FILE="$BATS_TEST_TMPDIR/missing/events.log"
	for LOGSHURU_OUTPUT in stderr split; do
		export LOGSHURU_OUTPUT
		run --separate-stderr invoke_logger library WARNING "stream warning"
		[ "$status" -ne 0 ]
		[ -z "$output" ]
		[[ "$stderr" == *"stream warning"*"Failed to append log file:"* ]]
	done
}
