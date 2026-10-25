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
}

@test "sourcing initializes the library silently without running the CLI" {
	run --separate-stderr bash -c 'source "$1"' bash "$LOGSHURU" INFO "must not be emitted"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
}

@test "child Bash processes do not inherit incomplete logging functions" {
	run --separate-stderr bash -c '
		source "$1"
		bash -c '\''
			for name in log get_log_level set_log_level; do
				if declare -F "$name"; then
					exit 1
				fi
			done
		'\''
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[ -z "$output" ]
	[ -z "$stderr" ]
}

@test "child Bash can log after explicitly sourcing the library" {
	run --separate-stderr bash -c '
		source "$1"
		bash -c '\''source "$1"; log INFO "child message"'\'' bash "$1"
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == *"child message"* ]]
	[ -z "$stderr" ]
}

@test "child initialization inherits exported threshold and isolates later changes" {
	run --separate-stderr bash -c '
		source "$1"
		set_log_level ERROR || exit
		bash -c '\''
			source "$1"
			[[ "$(get_log_level)" == ERROR ]] || exit 1
			log INFO "must be filtered" || exit
			set_log_level CRITICAL || exit
			log ERROR "must also be filtered" || exit
			log CRITICAL "child critical message"
		'\'' bash "$1" || exit
		[[ "$(get_log_level)" == ERROR ]]
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == *"child critical message"* ]]
	[[ "$output" != *"must be filtered"* ]]
	[[ "$output" != *"must also be filtered"* ]]
	[ -z "$stderr" ]
}

@test "parenthesized subshells still use the initialized library" {
	run --separate-stderr bash -c '
		source "$1"
		(log INFO "subshell message")
	' bash "$LOGSHURU"
	[ "$status" -eq 0 ]
	[[ "$output" == *"subshell message"* ]]
	[ -z "$stderr" ]
}
