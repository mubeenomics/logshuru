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
	local level="${1^^}"
	local message="${*:2}"

	if ! should_log "$level"; then return 0; fi

	local date file_path
	date=$(date +"%F %T.%3N")
	file_path="$(basename "${BASH_SOURCE[1]:-cli}")"

	local func_name="${FUNCNAME[1]:-main}"
	local line_no="${BASH_LINENO[0]:-0}"

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

	echo -e "${COLORS["GREEN"]}$date${COLORS["END"]} | $color$level_padded${COLORS["END"]} | ${COLORS["CYAN"]}$file_path${COLORS["END"]}:${COLORS["CYAN"]}$func_name${COLORS["END"]}:${COLORS["CYAN"]}$line_no${COLORS["END"]} - $color$message${COLORS["END"]}"
}

# Set log level
set_log_level() {
	local new_level="${1^^}"
	if [[ -n "${LOG_LEVELS[$new_level]}" ]]; then
		export LOG_LEVEL="$new_level"
		current_log_level="$new_level"
		log INFO "Current log level: $current_log_level"
		return 0
	else
		echo "Warning: '$new_level' is not a valid log level." >&2
		echo "Valid levels: " "${!LOG_LEVELS[@]}" >&2
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
	if [[ "$1" == "-h" || "$1" == "--help" ]]; then
		show_help
		exit 0
	fi

	if [[ "$1" == "-v" || "$1" == "--version" ]]; then
		echo "$0 v$VERSION"
		exit 0
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

# Export functions if sourced
if is_sourced; then
	export -f log
	export -f get_log_level
	export -f set_log_level

	log SUCCESS "Logging functions loaded successfully!"
	log INFO "Current log level: $(get_log_level)"
else
	main "$@"
fi
