#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != -- || $# -lt 2 ]]; then
	printf 'Usage: bash %s -- command [argument ...]\n' "${0##*/}" >&2
	exit 2
fi
shift

# Resolve the checkout's library without changing the command's working directory.
case "${BASH_SOURCE[0]}" in
*/*) script_dir=${BASH_SOURCE[0]%/*} ;;
*) script_dir=. ;;
esac
script_dir=$(CDPATH='' cd -- "$script_dir" && pwd -P)
export LOGSHURU_OUTPUT=${LOGSHURU_OUTPUT:-stderr}
# shellcheck source=../logshuru.sh
source "$script_dir/../logshuru.sh"

# Arguments may contain credentials; lifecycle records deliberately omit them.
# After initialization, logging is best-effort and never replaces command status.
log DEBUG "Runner initialized" || :
log INFO "Command started" || :
started=$SECONDS
if (command -- "$@"); then
	status=0
else
	status=$?
fi
elapsed=$((SECONDS - started))

if ((status == 0)); then
	log SUCCESS "Command completed exit=0 elapsed=${elapsed}s" || :
else
	log ERROR "Command failed exit=$status elapsed=${elapsed}s" || :
fi
exit "$status"
