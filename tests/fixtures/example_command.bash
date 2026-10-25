#!/usr/bin/env bash
set -euo pipefail

mode=$1
shift
case "$mode" in
streams)
	printf '%s\n' 'application data'
	printf '%s\n' 'tool diagnostic' >&2
	exit "$1"
	;;
arguments)
	# Emit NUL-delimited values for an exact, independent argv comparison.
	printf '%s\0' "$@"
	;;
directory) pwd -P ;;
esac
