#!/usr/bin/env bash
# Dark theme for the parts of the system that exist outside a user session:
# the login greeter, the text console, and the template for future user accounts.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected
need_sudo

step "Dark theme: greeter, console and new-user defaults"

if [ -d /usr/share/themes/PiXnoir ]; then
	GTK_THEME_NAME="PiXnoir"
elif [ -d /usr/share/themes/Adwaita-dark ]; then
	GTK_THEME_NAME="Adwaita-dark"
else
	GTK_THEME_NAME="Adwaita"
fi

# --- Login greeter ---------------------------------------------------------
# The screen people forget: without this the Pi flashes a white login screen on
# every boot before the dark desktop appears.
greeter="/etc/lightdm/pi-greeter.conf"
if [ -f "$greeter" ]; then
	ini_set "$greeter" greeter theme-name "$GTK_THEME_NAME"
	ini_set "$greeter" greeter desktop_bg '#1c1c1c'
elif [ -d /etc/lightdm ]; then
	warn "lightdm present but $greeter missing; greeter left alone"
else
	skip "lightdm not installed"
fi

# --- Text console ----------------------------------------------------------
# setvtrgb loads a palette into the virtual terminals. Doing this with a service
# rather than kernel arguments in cmdline.txt keeps a typo out of the boot path.
if has_cmd setvtrgb; then
	install_config console/vtrgb.dark /etc/vtrgb.dark
	write_file /etc/systemd/system/pi5-console-colors.service <<'UNIT'
# Managed by my-pi5-setup (scripts/33-dark-system.sh)
[Unit]
Description=Apply dark palette to the virtual consoles
After=systemd-vconsole-setup.service
Wants=systemd-vconsole-setup.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/setvtrgb /etc/vtrgb.dark

[Install]
WantedBy=multi-user.target
UNIT
	if [ "$DRY_RUN" != "1" ]; then
		sudo systemctl daemon-reload
		sudo systemctl enable --now pi5-console-colors.service >/dev/null 2>&1 \
			&& changed "console colour service enabled" \
			|| warn "could not enable pi5-console-colors.service"
	else
		dry "enable pi5-console-colors.service"
	fi
else
	skip "setvtrgb not available (console palette unchanged)"
fi

# --- Template for future accounts ------------------------------------------
# This is what makes the theme stick to the machine rather than to one account:
# any user created later starts dark without running anything.
step "Seeding /etc/skel"
# shellcheck source=../lib/theme-files.sh
. "$REPO_ROOT/lib/theme-files.sh"
for rel in "${SKEL_THEME_FILES[@]}"; do
	src="$TARGET_HOME/$rel"
	[ -f "$src" ] || continue
	write_file "/etc/skel/$rel" < "$src"
done

if [ -f /etc/skel/.bashrc ]; then
	ensure_line /etc/skel/.bashrc \
		'[ -r "$HOME/.config/my-pi5-setup/shell-dark.sh" ] && . "$HOME/.config/my-pi5-setup/shell-dark.sh"' \
		'my-pi5-setup/shell-dark\.sh'
fi

summary "dark-system"
