#!/usr/bin/env bash
# Bring a freshly flashed image up to date and set the machine-level basics.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected
need_sudo

step "Base system"

if [ "${SKIP_UPGRADE:-0}" = "1" ]; then
	skip "package upgrade (SKIP_UPGRADE=1)"
elif [ "$DRY_RUN" = "1" ]; then
	dry "apt-get full-upgrade"
else
	apt_update_once
	log "upgrading packages (this is the slow part on a fresh image)"
	sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y -qq
fi

# shellcheck disable=SC2086
apt_install $BASE_PACKAGES

step "Hostname, timezone, locale"

current_host="$(hostnamectl --static 2>/dev/null || cat /etc/hostname)"
if [ "$current_host" = "$PI_HOSTNAME" ]; then
	skip "hostname already $PI_HOSTNAME"
else
	run_change sudo hostnamectl set-hostname "$PI_HOSTNAME"
	# Keep /etc/hosts in step, or sudo warns about an unresolvable host on every call.
	ensure_line /etc/hosts "127.0.1.1	$PI_HOSTNAME" '^127\.0\.1\.1'
fi

current_tz="$(timedatectl show -p Timezone --value 2>/dev/null || echo unknown)"
if [ "$current_tz" = "$PI_TIMEZONE" ]; then
	skip "timezone already $PI_TIMEZONE"
else
	run_change sudo timedatectl set-timezone "$PI_TIMEZONE"
fi

if locale -a 2>/dev/null | grep -qi "^${PI_LOCALE//-/}$\|^${PI_LOCALE/.UTF-8/.utf8}$"; then
	skip "locale $PI_LOCALE already generated"
else
	ensure_line /etc/locale.gen "$PI_LOCALE UTF-8" "^#\?${PI_LOCALE} "
	run_change sudo locale-gen
	run_change sudo update-locale "LANG=$PI_LOCALE"
fi

summary "base"
