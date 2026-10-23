#!/bin/bash
set -euo pipefail

# shellcheck source=../../logshuru.sh
source "$1"

emit_context() {
	log INFO "function line=$LINENO"
}

outer_context() {
	emit_context
}

case "$2" in
top-level) log INFO "top-level line=$LINENO" ;;
function) emit_context ;;
nested) outer_context ;;
subshell) (log INFO "subshell line=$LINENO") ;;
helper)
	# shellcheck source=context_helper.bash
	source "$3"
	helper_context
	;;
cli) bash "$1" INFO "CLI from script" ;;
esac
