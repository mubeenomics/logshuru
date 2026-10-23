#!/bin/bash

# Constants
VERSION="1.0.0"
DEFAULT_LOG_LEVEL="PROCESS"

# ANSI color definitions
declare -A COLORS=(
	["RED_B"]='\e[1;31m'    # Bold Red
	["BLUE_B"]='\e[1;34m'   # Bold Blue
	["CYAN"]='\e[0;36m'     # Cyan (normal weight)
	["CYAN_B"]='\e[1;36m'   # Bold Cyan
	["GREEN"]='\e[0;32m'    # Green (normal weight)
	["GREEN_B"]='\e[1;32m'  # Bold Green
	["WHITE_B"]='\e[1;37m'  # Bold White
	["YELLOW_B"]='\e[1;33m' # Bold Yellow
	["PURPLE"]='\e[1;35m'   # Bold Purple/Magenta
	["RBWT"]='\e[1;41m'     # Bold text with Red background (White text)
	["END"]='\e[0m'         # Reset/End formatting
)

# Log level definitions
declare -A LOG_LEVELS=(
	["TRACE"]=0
	["DEBUG"]=1
	["PROCESS"]=2
	["INFO"]=3
	["SUCCESS"]=4
	["WARNING"]=5
	["ERROR"]=6
	["CRITICAL"]=7
)

# Initialize current log level
current_log_level=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}
current_log_level=${current_log_level^^}
if [[ -z "${LOG_LEVELS[$current_log_level]:-}" ]]; then
	printf 'Invalid LOG_LEVEL: %s\nValid levels: %s\n' "$LOG_LEVEL" "${!LOG_LEVELS[*]}" >&2
	if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
		return 1
	else
		exit 1
	fi
fi

# Display help
show_help() {
	echo -e "${COLORS["WHITE_B"]}$(basename "$0")${COLORS["END"]} - A Bash logger for color-coded logging with multiple log levels and context info."
	echo
	echo -e "${COLORS["WHITE_B"]}Usage:${COLORS["END"]}"
	echo -e "  As CLI tool:\t$(basename "$0") <log_level> <message>"
	echo -e "  As library:\tsource $(basename "$0")"
	echo -e "             \tlog <log_level> <message>"
	echo
	echo -e "${COLORS["WHITE_B"]}Examples:${COLORS["END"]}"
	echo -e "  $(basename "$0") INFO \"Application started\""
	echo -e "  $(basename "$0") ERROR \"Failed to connect to database\""
	echo -e "  source $(basename "$0") && log DEBUG \"Debug message\""
	echo
	echo -e "${COLORS["WHITE_B"]}Available log levels:${COLORS["END"]}"
	echo -e "  ${COLORS["CYAN_B"]}TRACE${COLORS["END"]}     - Detailed tracing information"
	echo -e "  ${COLORS["BLUE_B"]}DEBUG${COLORS["END"]}     - Debugging messages"
	echo -e "  ${COLORS["PURPLE"]}PROCESS${COLORS["END"]}   - Process-level messages (Default)"
	echo -e "  ${COLORS["WHITE_B"]}INFO${COLORS["END"]}      - General information"
	echo -e "  ${COLORS["GREEN_B"]}SUCCESS${COLORS["END"]}   - Successful operation"
	echo -e "  ${COLORS["YELLOW_B"]}WARNING${COLORS["END"]}   - Warning conditions"
	echo -e "  ${COLORS["RED_B"]}ERROR${COLORS["END"]}     - Error messages"
	echo -e "  ${COLORS["RBWT"]}CRITICAL${COLORS["END"]}  - Critical conditions"
	echo
	echo -e "${COLORS["WHITE_B"]}Log Level Filtering:${COLORS["END"]}"
	echo -e "  export LOG_LEVEL=DEBUG"
	echo -e "  set_log_level DEBUG"
	echo
	echo -e "${COLORS["WHITE_B"]}Author:${COLORS["END"]} Mohammed Mubeen Shaikh"
	echo -e "${COLORS["WHITE_B"]}Contact:${COLORS["END"]} mubeenomics@gmail.com"
}

# Check if log level should be printed
should_log() {
	local message_level=$1
	local current_level_num=${LOG_LEVELS[$current_log_level]}
	local message_level_num=${LOG_LEVELS[$message_level]}

	[[ -z "$current_level_num" ]] && current_level_num=${LOG_LEVELS[$DEFAULT_LOG_LEVEL]}
	[[ -z "$message_level_num" ]] && message_level_num=${LOG_LEVELS["PROCESS"]}

	[[ $message_level_num -ge $current_level_num ]]
}

# Logging function
log() {
	if [[ $# -lt 2 ]]; then
		printf 'Error: Missing required arguments\nUsage: log <log_level> <message>\n' >&2
		return 1
	fi

	local level="${1^^}"
	local message="${*:2}"

	local color=""
	local level_padded=""

	case "$level" in
	"TRACE")
		color="${COLORS["CYAN_B"]}"
		level_padded="TRACE   "
		;;
	"DEBUG")
		color="${COLORS["BLUE_B"]}"
		level_padded="DEBUG   "
		;;
	"PROCESS")
		color="${COLORS["PURPLE"]}"
		level_padded="PROCESS "
		;;
	"INFO")
		color="${COLORS["WHITE_B"]}"
		level_padded="INFO    "
		;;
	"SUCCESS")
		color="${COLORS["GREEN_B"]}"
		level_padded="SUCCESS "
		;;
	"WARNING")
		color="${COLORS["YELLOW_B"]}"
		level_padded="WARNING "
		;;
	"ERROR")
		color="${COLORS["RED_B"]}"
		level_padded="ERROR   "
		;;
	"CRITICAL")
		color="${COLORS["RBWT"]}"
		level_padded="CRITICAL"
		;;
	*)
		echo -e "${COLORS["RED_B"]}Invalid log level:${COLORS["END"]} $level" >&2
		echo -e "${COLORS["WHITE_B"]}Valid levels:${COLORS["END"]} ${!LOG_LEVELS[*]}" >&2
		return 1
		;;
	esac

	if ! should_log "$level"; then return 0; fi

	local date file_path
	date=$(date +"%F %T.%3N")
	local func_name line_no
	if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
		# A separate CLI process cannot inspect its invoking shell's call stack.
		file_path=cli
		func_name=cli
		line_no=0
	else
		file_path="$(basename "${BASH_SOURCE[1]:-unknown}")"
		func_name="${FUNCNAME[1]:-main}"
		line_no="${BASH_LINENO[0]:-0}"
	fi

	# Interpret escapes only in color definitions; render message and context literally.
	printf '%b%s%b | %b%s%b | %b%s%b:%b%s%b:%b%s%b - %b%s%b\n' \
		"${COLORS["GREEN"]}" "$date" "${COLORS["END"]}" \
		"$color" "$level_padded" "${COLORS["END"]}" \
		"${COLORS["CYAN"]}" "$file_path" "${COLORS["END"]}" \
		"${COLORS["CYAN"]}" "$func_name" "${COLORS["END"]}" \
		"${COLORS["CYAN"]}" "$line_no" "${COLORS["END"]}" \
		"$color" "$message" "${COLORS["END"]}"
}

# Set log level
set_log_level() {
	if [[ $# -ne 1 ]]; then
		printf 'Error: Expected exactly one log level\nUsage: set_log_level <log_level>\n' >&2
		return 1
	fi

	local new_level="$1"
	new_level=${new_level^^}
	if [[ -n "$new_level" && -n "${LOG_LEVELS[$new_level]:-}" ]]; then
		export LOG_LEVEL="$new_level"
		current_log_level="$new_level"
		# Propagate notification failures even when the caller handles our status.
		log INFO "Current log level: $current_log_level"
	else
		printf "Warning: '%s' is not a valid log level.\nValid levels: %s\n" \
			"$new_level" "${!LOG_LEVELS[*]}" >&2
		return 1
	fi
}

# Get current log level
get_log_level() {
	echo "$current_log_level"
}

# Check if script is sourced
is_sourced() {
	[[ "${BASH_SOURCE[0]}" != "${0}" ]]
}

# CLI entrypoint
main() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		show_help
		return
	fi

	if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
		echo "$0 v$VERSION"
		return
	fi

	if [[ $# -lt 2 ]]; then
		echo -e "${COLORS["RED_B"]}Error: Missing required arguments${COLORS["END"]}" >&2
		echo "Usage: $(basename "$0") <log_level> <message>" >&2
		echo "Try '$(basename "$0") --help' for more information." >&2
		exit 1
	fi

	local log_level="$1"
	local message="${*:2}"
	log "$log_level" "$message"
}

# Child Bash processes must source the library to initialize functions and state.
if ! is_sourced; then
	main "$@"
fi
