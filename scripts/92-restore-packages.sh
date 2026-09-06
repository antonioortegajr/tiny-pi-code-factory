#!/usr/bin/env bash
# Reinstall the hand-installed packages recorded by 90-capture.sh.
#
# Anything no longer in the archive (an OS upgrade renamed or dropped it) is
# reported and skipped rather than aborting the run.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected
need_sudo

list="$REPO_ROOT/captured/packages/manual.txt"

step "Restoring packages from captured/packages/manual.txt"

[ -f "$list" ] || { log "no capture found; run 'make capture' on the old install first"; exit 0; }

wanted=()
while read -r pkg; do
	[ -n "$pkg" ] || continue
	case "$pkg" in \#*) continue ;; esac
	wanted+=("$pkg")
done < "$list"

log "${#wanted[@]} package(s) in the capture"
apt_update_once
apt_install_optional "${wanted[@]}"

summary "restore-packages"
