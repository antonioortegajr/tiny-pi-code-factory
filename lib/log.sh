#!/usr/bin/env bash
# Logging helpers. Sourced by every script.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
	C_RESET=$'\033[0m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'
	C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[34m'
else
	C_RESET=''; C_DIM=''; C_BOLD=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''
fi

# Counters, reported by summary().
CHANGE_COUNT=0
SKIP_COUNT=0
WARN_COUNT=0

step()    { printf '\n%s==> %s%s\n' "$C_BOLD$C_BLU" "$*" "$C_RESET"; }
log()     { printf '    %s\n' "$*"; }
changed() { CHANGE_COUNT=$((CHANGE_COUNT + 1)); printf '    %s+%s %s\n' "$C_GRN" "$C_RESET" "$*"; }
skip()    { SKIP_COUNT=$((SKIP_COUNT + 1)); printf '    %s=%s %s\n' "$C_DIM" "$C_RESET" "${C_DIM}$*${C_RESET}"; }
warn()    { WARN_COUNT=$((WARN_COUNT + 1)); printf '    %s!%s %s\n' "$C_YEL" "$C_RESET" "$*" >&2; }
die()     { printf '\n%sERROR:%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$*" >&2; exit 1; }
dry()     { printf '    %s~%s %s\n' "$C_YEL" "$C_RESET" "${C_DIM}would $*${C_RESET}"; }

summary() {
	printf '\n%s%s:%s %d changed, %d already correct' \
		"$C_BOLD" "${1:-done}" "$C_RESET" "$CHANGE_COUNT" "$SKIP_COUNT"
	[ "$WARN_COUNT" -gt 0 ] && printf ', %s%d warnings%s' "$C_YEL" "$WARN_COUNT" "$C_RESET"
	printf '\n'
}
