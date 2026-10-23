#!/usr/bin/env bats

# Literal-message fixtures must retain shell expressions without expanding them.
# shellcheck disable=SC2016

bats_require_minimum_version 1.5.0

# shellcheck source=test_helper.bash
source "$BATS_TEST_DIRNAME/test_helper.bash"

setup() {
	LOGSHURU="$BATS_TEST_DIRNAME/../logshuru.sh"
	export LOG_LEVEL=PROCESS
}

assert_message_preserved() {
	local message="$1"
	local mode
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "$message"
		[ "$status" -eq 0 ]
		[ -z "$stderr" ]
		# Match the entire message suffix, including the logger's color reset.
		[[ "$output" == *" - "$'\e[1;37m'"$message"$'\e[0m' ]]
	done
}

@test "literal backslash escapes are preserved in both modes" {
	assert_message_preserved 'paths: C:\new\test; escapes: \n \t \r \b \\ \x41 \u0041 \033[31m'
}

@test "literal backslash-c does not truncate the message or color reset" {
	assert_message_preserved 'before \c after'
}

@test "percent signs and format directives are preserved in both modes" {
	assert_message_preserved '100% complete: %s %b %d %n %%'
}

@test "quotes and shell metacharacters are preserved in both modes" {
	assert_message_preserved '"quoted" '\''single quoted'\'' $HOME $(exit 99) `exit 99` * ; & |'
}

@test "actual tabs and Unicode are preserved in both modes" {
	assert_message_preserved $'sample\tαβγ\t✓ café'
}

@test "multiline messages including trailing newlines are preserved in both modes" {
	assert_message_preserved $'first line\n\nthird line\n\n'
}

@test "empty messages and surrounding whitespace are preserved in both modes" {
	assert_message_preserved ''
	assert_message_preserved '  padded message  '
}

@test "logger colors are still emitted as ANSI escape sequences" {
	for mode in cli library; do
		run --separate-stderr invoke_logger "$mode" INFO "colored message"
		[ "$status" -eq 0 ]
		[ -z "$stderr" ]
		[[ "$output" == $'\e[0;32m'* ]]
		[[ "$output" == *$'\e[1;37mINFO    \e[0m'* ]]
		[[ "$output" == *$'\e[1;37mcolored message\e[0m' ]]
	done
}

@test "every level uses its documented ANSI color in both modes" {
	export LOG_LEVEL=TRACE
	local levels=(TRACE DEBUG PROCESS INFO SUCCESS WARNING ERROR CRITICAL)
	local colors=(
		$'\e[1;36m' $'\e[1;34m' $'\e[1;35m' $'\e[1;37m'
		$'\e[1;32m' $'\e[1;33m' $'\e[1;31m' $'\e[1;41m'
	)
	local mode index padded
	for mode in cli library; do
		for index in "${!levels[@]}"; do
			run --separate-stderr invoke_logger "$mode" "${levels[$index]}" "level color"
			[ "$status" -eq 0 ]
			[ -z "$stderr" ]
			printf -v padded '%-8s' "${levels[$index]}"
			[[ "$output" == *" | ${colors[$index]}${padded}"$'\e[0m | '* ]]
			[[ "$output" == *" - ${colors[$index]}level color"$'\e[0m' ]]
		done
	done
}
