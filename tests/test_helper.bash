invoke_logger() {
	local mode="$1"
	shift
	if [[ "$mode" == cli ]]; then
		bash "$LOGSHURU" "$@"
	else
		bash -c 'source "$1" || exit; shift; log "$@"' bash "$LOGSHURU" "$@"
	fi
}
