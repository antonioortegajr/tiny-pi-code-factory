#!/usr/bin/env bash
# Modest hardening: key-only SSH, a firewall, and automatic security updates.
#
# The SSH change refuses to apply unless an authorized key is already in place,
# so running this over SSH cannot lock you out of your own Pi.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected
need_sudo

step "SSH"

auth_keys="$TARGET_HOME/.ssh/authorized_keys"
if [ "${SSH_DISABLE_PASSWORDS:-0}" != "1" ]; then
	skip "password login left enabled (SSH_DISABLE_PASSWORDS=0)"
elif [ ! -s "$auth_keys" ]; then
	warn "no keys in $auth_keys - refusing to disable password login"
	log "copy a key first, from your Mac:  ssh-copy-id $TARGET_USER@$PI_HOSTNAME.local"
else
	log "$(grep -c . "$auth_keys") key(s) present in authorized_keys"

	# ~/.ssh may be bind-mounted from the SSD (see 25-ssd-state.sh). If that mount
	# ever fails, key auth would break with passwords already disabled - which is
	# a lockout. Keep a second copy on the boot drive and have sshd read both.
	# Public keys are not secret, so a root-owned 0644 copy costs nothing.
	if mountpoint -q "$TARGET_HOME/.ssh" 2>/dev/null; then
		tmp="$(mktemp)"
		cat "$auth_keys" > "$tmp"
		write_file "/etc/ssh/authorized_keys.d/$TARGET_USER" 0644 < "$tmp"
		rm -f "$tmp"
		log "fallback copy kept on the boot drive in case the SSD does not mount"
	fi

	write_file /etc/ssh/sshd_config.d/99-my-pi5-setup.conf <<'SSHD'
# Managed by my-pi5-setup (scripts/50-harden.sh)
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no

# Second path is the boot-drive fallback for a bind-mounted ~/.ssh.
AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys.d/%u
SSHD
	if [ "$DRY_RUN" != "1" ]; then
		if sudo sshd -t; then
			sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd
			log "sshd reloaded; existing sessions stay connected"
		else
			warn "sshd config test failed; reverting"
			sudo rm -f /etc/ssh/sshd_config.d/99-my-pi5-setup.conf
		fi
	fi
fi

step "Firewall"

if [ "${ENABLE_UFW:-0}" = "1" ]; then
	apt_install_optional ufw
	if has_cmd ufw; then
		if sudo ufw status 2>/dev/null | grep -q '^Status: active'; then
			skip "ufw already active"
		elif [ "$DRY_RUN" = "1" ]; then
			dry "allow ssh and enable ufw"
		else
			# Allow SSH before enabling, or enabling drops the session.
			sudo ufw allow OpenSSH >/dev/null 2>&1 || sudo ufw allow 22/tcp >/dev/null
			sudo ufw --force enable >/dev/null
			changed "ufw enabled with SSH allowed"
		fi
	fi
else
	skip "ufw disabled"
fi

step "Automatic security updates"

if [ "${ENABLE_UNATTENDED_UPGRADES:-0}" = "1" ]; then
	apt_install_optional unattended-upgrades
	if pkg_installed unattended-upgrades; then
		write_file /etc/apt/apt.conf.d/20auto-upgrades <<'APT'
// Managed by my-pi5-setup (scripts/50-harden.sh)
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT
	fi
else
	skip "unattended-upgrades disabled"
fi

summary "harden"
