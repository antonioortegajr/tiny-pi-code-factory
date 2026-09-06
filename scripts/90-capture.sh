#!/usr/bin/env bash
# Record what this Pi currently looks like, into captured/, so the next reformat
# restores what you actually had rather than what you remembered to write down.
#
# Nothing here is applied automatically - it is a reference you read and a
# package list you can feed back in with:  make restore-packages
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected

out="$REPO_ROOT/captured"

step "Capturing system state into captured/"

save() {  # save <filename> <command...>
	local name="$1"; shift
	local tmp; tmp="$(mktemp)"
	if "$@" > "$tmp" 2>/dev/null; then
		write_file "$out/$name" < "$tmp"
	else
		skip "$name (command unavailable)"
	fi
	rm -f "$tmp"
}

copy() {  # copy <destination name> <source path>
	local name="$1" src="$2" tmp
	[ -e "$src" ] || { skip "$name (not present)"; return 0; }
	tmp="$(mktemp)"
	if [ -r "$src" ]; then cat "$src" > "$tmp"; else sudo cat "$src" > "$tmp"; fi
	write_file "$out/$name" < "$tmp"
	rm -f "$tmp"
}

# Hand-installed packages only - the list you would want to reinstall.
save packages/manual.txt apt-mark showmanual
save packages/all.txt dpkg-query -W -f='${binary:Package}\t${Version}\n'
save packages/repos.txt sh -c 'grep -rhs "^deb " /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null'

save system/lsblk.txt lsblk -o NAME,SIZE,TYPE,TRAN,FSTYPE,UUID,MOUNTPOINT
save system/services.txt systemctl list-unit-files --state=enabled --no-pager
save system/os-release.txt cat /etc/os-release
# -n so a capture never blocks on a password prompt.
save system/eeprom.txt sudo -n rpi-eeprom-config

copy system/fstab /etc/fstab
copy system/config.txt /boot/firmware/config.txt
copy system/cmdline.txt /boot/firmware/cmdline.txt

save user/crontab.txt as_user crontab -l
save user/groups.txt id "$TARGET_USER"

# VS Code extensions, if any - reinstalling these by hand is tedious.
if has_cmd code; then
	save user/vscode-extensions.txt as_user code --list-extensions
fi

log "written to captured/ - review and commit"
summary "capture"
