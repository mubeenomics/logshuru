#!/bin/bash

# Global associative arrays require declare -g (introduced in Bash 4.2).
if ((BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 2))); then
	printf 'Error: logshuru requires Bash 4.2 or later\n' >&2
	if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
		return 1
	else
		exit 1
	fi
fi

# Internal state and helpers use a reserved project namespace.
_logshuru_version="2.0.0"
_logshuru_default_log_level="PROCESS"
_logshuru_valid_levels='TRACE DEBUG PROCESS INFO SUCCESS WARNING ERROR CRITICAL'

# ANSI color definitions
# Separate declaration from assignment for Bash 4.2's function-sourcing behavior.
declare -gA _logshuru_colors
_logshuru_colors=(
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
declare -gA _logshuru_levels
_logshuru_levels=(
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
_logshuru_current_log_level=${LOG_LEVEL:-$_logshuru_default_log_level}
_logshuru_current_log_level=${_logshuru_current_log_level^^}
if [[ -z "${_logshuru_levels[$_logshuru_current_log_level]:-}" ]]; then
	printf 'Invalid LOG_LEVEL: %s\nValid levels: %s\n' "$LOG_LEVEL" "$_logshuru_valid_levels" >&2
	if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
		return 1
	else
		exit 1
	fi
fi

# New output settings are read at initialization, like LOG_LEVEL.
_logshuru_color_mode=${LOGSHURU_COLOR:-auto}
_logshuru_color_mode=${_logshuru_color_mode,,}
case "$_logshuru_color_mode" in
auto | always | never) ;;
*)
	printf 'Invalid LOGSHURU_COLOR: %s\nValid modes: auto always never\n' "$LOGSHURU_COLOR" >&2
	if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
		return 1
	else
		exit 1
	fi
	;;
esac

_logshuru_output_mode=${LOGSHURU_OUTPUT:-stdout}
_logshuru_output_mode=${_logshuru_output_mode,,}
case "$_logshuru_output_mode" in
stdout | stderr | split) ;;
*)
	printf 'Invalid LOGSHURU_OUTPUT: %s\nValid modes: stdout stderr split\n' "$LOGSHURU_OUTPUT" >&2
	if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
		return 1
	else
		exit 1
	fi
	;;
esac

_logshuru_timestamp_format=${LOGSHURU_TIMESTAMP_FORMAT:-'%F %T.%3N'}
_logshuru_timezone=${LOGSHURU_TZ:-}
_logshuru_zoneinfo_dir=${TZDIR:-/usr/share/zoneinfo}
if [[ -n "$_logshuru_timezone" && "$_logshuru_timezone" != UTC ]] &&
	[[ ! "$_logshuru_timezone" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ||
		! -f "$_logshuru_zoneinfo_dir/$_logshuru_timezone" ]]; then
	printf 'Invalid LOGSHURU_TZ: %s\nUse UTC or an installed IANA timezone name.\n' "$LOGSHURU_TZ" >&2
	if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
		return 1
	else
		exit 1
	fi
fi

_logshuru_file=${LOGSHURU_FILE:-}
case "$_logshuru_file" in
"" | /*) ;;
*) _logshuru_file="$PWD/$_logshuru_file" ;;
esac

_logshuru_format=${LOGSHURU_FORMAT:-text}
_logshuru_format=${_logshuru_format,,}
case "$_logshuru_format" in
text | json) ;;
*)
	printf 'Invalid LOGSHURU_FORMAT: %s\nValid formats: text json\n' "$LOGSHURU_FORMAT" >&2
	if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
		return 1
	else
		exit 1
	fi
	;;
esac

# Explicit overrides apply only to date, leaving the caller's TZ unchanged.
_logshuru_timestamp() {
	case "$_logshuru_timezone" in
	UTC) TZ=UTC0 date +"$_logshuru_timestamp_format" ;;
	"") date +"$_logshuru_timestamp_format" ;;
	*) TZDIR="$_logshuru_zoneinfo_dir" TZ=":$_logshuru_timezone" date +"$_logshuru_timestamp_format" ;;
	esac
}

# Detect the actual destination at emission time, including per-call redirection.
_logshuru_color_enabled() {
	case "$_logshuru_color_mode" in
	always) return 0 ;;
	never) return 1 ;;
	auto) [[ -t "${1:-1}" && -z "${NO_COLOR:-}" && "${TERM:-}" != dumb ]] ;;
	esac
}

# Escape a UTF-8 string into a caller-local destination variable (Bash 4 compatible).
# Byte iteration preserves Unicode and lets us reject malformed UTF-8 explicitly.
_logshuru_json_string() {
	local LC_ALL=C
	local _json_input="$1" _json_result="" _json_character _json_code _json_escape _json_index
	local _json_remaining=0 _json_min=128 _json_max=191
	for ((_json_index = 0; _json_index < ${#_json_input}; _json_index++)); do
		_json_character=${_json_input:_json_index:1}
		printf -v _json_code '%d' "'$_json_character"
		if ((_json_remaining > 0)); then
			((_json_code >= _json_min && _json_code <= _json_max)) || return 1
			_json_remaining=$((_json_remaining - 1))
			_json_min=128
			_json_max=191
		elif ((_json_code >= 128)); then
			_json_min=128
			_json_max=191
			if ((_json_code >= 194 && _json_code <= 223)); then
				_json_remaining=1
			elif ((_json_code >= 224 && _json_code <= 239)); then
				_json_remaining=2
				if ((_json_code == 224)); then _json_min=160; fi
				if ((_json_code == 237)); then _json_max=159; fi
			elif ((_json_code >= 240 && _json_code <= 244)); then
				_json_remaining=3
				if ((_json_code == 240)); then _json_min=144; fi
				if ((_json_code == 244)); then _json_max=143; fi
			else
				return 1
			fi
		fi
		case "$_json_code" in
		34) _json_result+='\"' ;;
		92) _json_result+="\\\\" ;;
		*)
			if ((_json_code < 32)); then
				printf -v _json_escape '\\u%04x' "$_json_code"
				_json_result+="$_json_escape"
			else
				_json_result+="$_json_character"
			fi
			;;
		esac
	done
	((_json_remaining == 0)) || return 1
	printf -v "$2" '"%s"' "$_json_result"
}

# Display help
_logshuru_show_help() {
	local -A help_colors=()
	local name
	for name in "${!_logshuru_colors[@]}"; do help_colors[$name]=""; done
	if _logshuru_color_enabled 1; then
		for name in "${!_logshuru_colors[@]}"; do help_colors[$name]="${_logshuru_colors[$name]}"; done
	fi

	echo -e "${help_colors["WHITE_B"]}${0##*/}${help_colors["END"]} - A Bash logger for color-coded logging with multiple log levels and context info."
	echo
	echo -e "${help_colors["WHITE_B"]}Usage:${help_colors["END"]}"
	echo -e "  As CLI tool:\t${0##*/} <log_level> <message>"
	echo -e "  As library:\tsource ${0##*/}"
	echo -e "             \tlog <log_level> <message>"
	echo
	echo -e "${help_colors["WHITE_B"]}Examples:${help_colors["END"]}"
	echo -e "  ${0##*/} INFO \"Application started\""
	echo -e "  ${0##*/} ERROR \"Failed to connect to database\""
	echo -e "  source ${0##*/} && log DEBUG \"Debug message\""
	echo
	echo -e "${help_colors["WHITE_B"]}Available log levels:${help_colors["END"]}"
	echo -e "  ${help_colors["CYAN_B"]}TRACE${help_colors["END"]}     - Detailed tracing information"
	echo -e "  ${help_colors["BLUE_B"]}DEBUG${help_colors["END"]}     - Debugging messages"
	echo -e "  ${help_colors["PURPLE"]}PROCESS${help_colors["END"]}   - Process-level messages (Default)"
	echo -e "  ${help_colors["WHITE_B"]}INFO${help_colors["END"]}      - General information"
	echo -e "  ${help_colors["GREEN_B"]}SUCCESS${help_colors["END"]}   - Successful operation"
	echo -e "  ${help_colors["YELLOW_B"]}WARNING${help_colors["END"]}   - Warning conditions"
	echo -e "  ${help_colors["RED_B"]}ERROR${help_colors["END"]}     - Error messages"
	echo -e "  ${help_colors["RBWT"]}CRITICAL${help_colors["END"]}  - Critical conditions"
	echo
	echo -e "${help_colors["WHITE_B"]}Log Level Filtering:${help_colors["END"]}"
	echo -e "  export LOG_LEVEL=DEBUG"
	echo -e "  set_log_level DEBUG"
	echo
	echo -e "${help_colors["WHITE_B"]}Colors:${help_colors["END"]}"
	echo "  LOGSHURU_COLOR=auto|always|never (default: auto)"
	echo "  Auto colors terminal output only; always/never override detection."
	echo "  In auto mode, nonempty NO_COLOR or TERM=dumb disables colors."
	echo
	echo -e "${help_colors["WHITE_B"]}Output:${help_colors["END"]}"
	echo "  LOGSHURU_OUTPUT=stdout|stderr|split (default: stdout)"
	echo "  Split sends WARNING and above to stderr; lower levels to stdout."
	echo "  Usage errors use stderr; help, version, and get_log_level use stdout."
	echo
	echo -e "${help_colors["WHITE_B"]}Timestamps:${help_colors["END"]}"
	echo '  LOGSHURU_TIMESTAMP_FORMAT: GNU date format (default: %F %T.%3N)'
	echo "  LOGSHURU_TZ: UTC or installed IANA name (default: inherited TZ/local time)"
	echo
	echo -e "${help_colors["WHITE_B"]}File logging:${help_colors["END"]}"
	echo "  LOGSHURU_FILE: append plain-text copies alongside stream output (default: off)"
	echo "  Relative paths are anchored at startup/sourcing; parent directories must exist."
	echo
	echo -e "${help_colors["WHITE_B"]}Format:${help_colors["END"]}"
	echo "  LOGSHURU_FORMAT=text|json (default: text)"
	echo "  JSON emits one UTF-8 object per event, without logger colors."
	echo
	echo -e "${help_colors["WHITE_B"]}Author:${help_colors["END"]} Mohammed Mubeen Shaikh"
	echo -e "${help_colors["WHITE_B"]}Contact:${help_colors["END"]} mubeenomics@gmail.com"
}

# Check if log level should be printed
_logshuru_should_log() {
	local message_level=$1
	local current_level_num=${_logshuru_levels[$_logshuru_current_log_level]}
	local message_level_num=${_logshuru_levels[$message_level]}

	[[ -z "$current_level_num" ]] && current_level_num=${_logshuru_levels[$_logshuru_default_log_level]}
	[[ -z "$message_level_num" ]] && message_level_num=${_logshuru_levels["PROCESS"]}

	[[ $message_level_num -ge $current_level_num ]]
}

# Public entry points skip their wrapper frame when capturing application context.
log() {
	_logshuru_emit 2 "$@"
}

# The frame offset is explicit and local to this emission, including setter calls.
_logshuru_emit() {
	local caller_frame=$1
	shift
	if [[ $# -lt 2 ]]; then
		printf 'Error: Missing required arguments\nUsage: log <log_level> <message>\n' >&2
		return 1
	fi

	local IFS=' '
	local level="${1^^}"
	local message="${*:2}"

	local color=""
	local level_padded=""

	case "$level" in
	"TRACE")
		color="${_logshuru_colors["CYAN_B"]}"
		level_padded="TRACE   "
		;;
	"DEBUG")
		color="${_logshuru_colors["BLUE_B"]}"
		level_padded="DEBUG   "
		;;
	"PROCESS")
		color="${_logshuru_colors["PURPLE"]}"
		level_padded="PROCESS "
		;;
	"INFO")
		color="${_logshuru_colors["WHITE_B"]}"
		level_padded="INFO    "
		;;
	"SUCCESS")
		color="${_logshuru_colors["GREEN_B"]}"
		level_padded="SUCCESS "
		;;
	"WARNING")
		color="${_logshuru_colors["YELLOW_B"]}"
		level_padded="WARNING "
		;;
	"ERROR")
		color="${_logshuru_colors["RED_B"]}"
		level_padded="ERROR   "
		;;
	"CRITICAL")
		color="${_logshuru_colors["RBWT"]}"
		level_padded="CRITICAL"
		;;
	*)
		local error_color="" error_reset=""
		if _logshuru_color_enabled 2; then
			error_color="${_logshuru_colors["RED_B"]}"
			error_reset="${_logshuru_colors["END"]}"
		fi
		printf '%bInvalid log level:%b %s\nValid levels: %s\n' \
			"$error_color" "$error_reset" "$level" "$_logshuru_valid_levels" >&2
		return 1
		;;
	esac

	if ! _logshuru_should_log "$level"; then return 0; fi

	local output_fd=1
	case "$_logshuru_output_mode" in
	stderr) output_fd=2 ;;
	split)
		case "$level" in WARNING | ERROR | CRITICAL) output_fd=2 ;; esac
		;;
	esac

	local date file_path
	if ! date=$(_logshuru_timestamp); then
		printf 'Error: Failed to generate log timestamp\n' >&2
		return 1
	fi
	local func_name line_no
	if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
		# A separate CLI process cannot inspect its invoking shell's call stack.
		file_path=cli
		func_name=cli
		line_no=0
	else
		file_path="${BASH_SOURCE[$caller_frame]:-unknown}"
		file_path="${file_path##*/}"
		func_name="${FUNCNAME[$caller_frame]:-main}"
		line_no="${BASH_LINENO[$((caller_frame - 1))]:-0}"
	fi

	local stream_record file_record
	if [[ "$_logshuru_format" == json ]]; then
		local json_timestamp json_level json_file json_function json_message
		if ! _logshuru_json_string "$date" json_timestamp ||
			! _logshuru_json_string "$level" json_level ||
			! _logshuru_json_string "$file_path" json_file ||
			! _logshuru_json_string "$func_name" json_function ||
			! _logshuru_json_string "$message" json_message; then
			printf 'Error: JSON fields must contain valid UTF-8\n' >&2
			return 1
		fi
		printf -v stream_record '{"timestamp":%s,"level":%s,"file":%s,"function":%s,"line":%s,"message":%s}\n' \
			"$json_timestamp" "$json_level" "$json_file" "$json_function" "$line_no" "$json_message"
		file_record="$stream_record"
	else
		local timestamp_color="${_logshuru_colors["GREEN"]}" context_color="${_logshuru_colors["CYAN"]}" reset="${_logshuru_colors["END"]}"
		if ! _logshuru_color_enabled "$output_fd"; then
			color=""
			timestamp_color=""
			context_color=""
			reset=""
		fi
		# Interpret escapes only in colors; render message and context literally.
		printf -v stream_record '%b%s%b | %b%s%b | %b%s%b:%b%s%b:%b%s%b - %b%s%b\n' \
			"$timestamp_color" "$date" "$reset" \
			"$color" "$level_padded" "$reset" \
			"$context_color" "$file_path" "$reset" \
			"$context_color" "$func_name" "$reset" \
			"$context_color" "$line_no" "$reset" \
			"$color" "$message" "$reset"
		printf -v file_record '%s | %s | %s:%s:%s - %s\n' \
			"$date" "$level_padded" "$file_path" "$func_name" "$line_no" "$message"
	fi

	local output_status=0
	if ! printf '%s' "$stream_record" >&"$output_fd"; then
		output_status=1
	fi

	# Attempt both destinations independently, even if the stream write failed.
	if [[ -n "$_logshuru_file" ]]; then
		if [[ -e "$_logshuru_file" && ! -f "$_logshuru_file" ]]; then
			printf 'Error: Log file is not a regular file: %s\n' "$_logshuru_file" >&2
			output_status=1
		elif ! printf '%s' "$file_record" >>"$_logshuru_file"; then
			printf 'Error: Failed to append log file: %s\n' "$_logshuru_file" >&2
			output_status=1
		fi
	fi
	return "$output_status"
}

# Set log level
set_log_level() {
	if [[ $# -ne 1 ]]; then
		printf 'Error: Expected exactly one log level\nUsage: set_log_level <log_level>\n' >&2
		return 1
	fi

	local new_level="$1"
	new_level=${new_level^^}
	if [[ -n "$new_level" && -n "${_logshuru_levels[$new_level]:-}" ]]; then
		export LOG_LEVEL="$new_level"
		_logshuru_current_log_level="$new_level"
		# Propagate notification failures even when the caller handles our status.
		_logshuru_emit 2 INFO "Current log level: $_logshuru_current_log_level"
	else
		printf "Warning: '%s' is not a valid log level.\nValid levels: %s\n" \
			"$new_level" "$_logshuru_valid_levels" >&2
		return 1
	fi
}

# Get current log level
get_log_level() {
	echo "$_logshuru_current_log_level"
}

# Check if script is sourced
_logshuru_is_sourced() {
	[[ "${BASH_SOURCE[0]}" != "${0}" ]]
}

# CLI entrypoint
_logshuru_main() {
	if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
		_logshuru_show_help
		return
	fi

	if [[ "${1:-}" == "-v" || "${1:-}" == "--version" ]]; then
		printf '%s v%s\n' "${0##*/}" "$_logshuru_version"
		return
	fi

	if [[ $# -lt 2 ]]; then
		local error_color="" reset=""
		if _logshuru_color_enabled 2; then
			error_color="${_logshuru_colors["RED_B"]}"
			reset="${_logshuru_colors["END"]}"
		fi
		printf '%bError: Missing required arguments%b\n' "$error_color" "$reset" >&2
		echo "Usage: ${0##*/} <log_level> <message>" >&2
		echo "Try '${0##*/} --help' for more information." >&2
		exit 1
	fi

	log "$@"
}

# Child Bash processes must source the library to initialize functions and state.
if ! _logshuru_is_sourced; then
	_logshuru_main "$@"
fi
