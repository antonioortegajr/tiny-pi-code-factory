#!/usr/bin/env bash
# The set of files that carry "dark theme" on a Raspberry Pi OS desktop.
# Shared by the skel seeding, the capture script and the replay script, so the
# three can never drift apart.

# Paths relative to the target user's home.
HOME_THEME_FILES=(
	.config/gtk-3.0/settings.ini
	.config/gtk-4.0/settings.ini
	.config/environment.d/99-dark-theme.conf
	.config/labwc/rc.xml
	.config/labwc/themerc-override
	.config/wayfire.ini
	.config/wf-panel-pi.ini
	.config/lxterminal/lxterminal.conf
	.config/dircolors
	.config/my-pi5-setup/shell-dark.sh
	.config/tmux/dark.conf
	.config/qt5ct/qt5ct.conf
	.config/pcmanfm/LXDE-pi/desktop-items-0.conf
	.config/Thonny/configuration.ini
	.config/geany/geany.conf
)

# What a brand new account needs. Deliberately narrower than the list above:
# compositor and panel configs are per-session state, not defaults worth copying.
SKEL_THEME_FILES=(
	.config/gtk-3.0/settings.ini
	.config/gtk-4.0/settings.ini
	.config/environment.d/99-dark-theme.conf
	.config/labwc/themerc-override
	.config/lxterminal/lxterminal.conf
	.config/dircolors
	.config/my-pi5-setup/shell-dark.sh
	.config/tmux/dark.conf
)

# Absolute system paths.
SYSTEM_THEME_FILES=(
	/etc/lightdm/pi-greeter.conf
	/etc/chromium.d/99-dark-mode
	/etc/profile.d/99-dark-theme.sh
	/etc/vtrgb.dark
)
