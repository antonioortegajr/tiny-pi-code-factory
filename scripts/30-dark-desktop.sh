#!/usr/bin/env bash
# Dark theme for the desktop shell: GTK apps, window decorations, panel,
# desktop background and Qt apps.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected

step "Dark theme: desktop"

if [ "${HAS_DESKTOP:-0}" != "1" ]; then
	log "no desktop on this image, nothing to theme here"
	summary "dark-desktop"; exit 0
fi

# Raspberry Pi OS ships PiXnoir, the dark sibling of its default PiXflat theme.
# Fall back to Adwaita-dark on anything that does not have it.
if [ -d /usr/share/themes/PiXnoir ]; then
	GTK_THEME_NAME="PiXnoir"
elif [ -d /usr/share/themes/Adwaita-dark ]; then
	GTK_THEME_NAME="Adwaita-dark"
else
	GTK_THEME_NAME="Adwaita"
	warn "no dark GTK theme found; relying on gtk-application-prefer-dark-theme only"
fi
log "GTK theme: $GTK_THEME_NAME"

# --- GTK 3 and GTK 4 -------------------------------------------------------
# Edit keys in place rather than replacing the file: Raspberry Pi's Appearance
# Settings stores the user's font and size in here too.
for ver in 3.0 4.0; do
	ini="$TARGET_HOME/.config/gtk-$ver/settings.ini"
	ini_set "$ini" Settings gtk-theme-name "$GTK_THEME_NAME"
	ini_set "$ini" Settings gtk-application-prefer-dark-theme 1
done

# GTK4 / libadwaita apps ignore settings.ini and read this instead.
if has_cmd gsettings; then
	if as_user gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null; then
		changed "gsettings color-scheme=prefer-dark"
		as_user gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME" 2>/dev/null || true
	else
		warn "gsettings failed (no session bus?); rerun 'make dark' from the Pi desktop"
	fi
fi

# --- Force the theme for every toolkit, including apps started by the panel --
# environment.d covers systemd-user-launched and dbus-activated apps; profile.d
# covers login shells and session scripts. Both are cheap, so set both.
write_file "$TARGET_HOME/.config/environment.d/99-dark-theme.conf" <<ENV
# Managed by my-pi5-setup (scripts/30-dark-desktop.sh)
GTK_THEME=$GTK_THEME_NAME
QT_QPA_PLATFORMTHEME=gtk3
ENV

write_file /etc/profile.d/99-dark-theme.sh <<ENV
# Managed by my-pi5-setup (scripts/30-dark-desktop.sh)
export GTK_THEME=$GTK_THEME_NAME
export QT_QPA_PLATFORMTHEME=gtk3
ENV

# Lets Qt apps pick up the GTK dark theme instead of rendering light.
apt_install_optional qt5-gtk-platformtheme qt6-gtk-platformtheme

# --- Window decorations ----------------------------------------------------
case "$COMPOSITOR" in
	labwc)
		# themerc-override tweaks individual colours of the active theme, which is
		# more durable than depending on a theme name that changes between releases.
		install_config labwc/themerc-override "$TARGET_HOME/.config/labwc/themerc-override"

		rc="$TARGET_HOME/.config/labwc/rc.xml"
		# Seed from the system default so we never drop labwc's stock keybindings.
		if [ ! -f "$rc" ] && [ -f /etc/xdg/labwc/rc.xml ]; then
			write_file "$rc" < /etc/xdg/labwc/rc.xml
		fi
		if [ -f "$rc" ] && has_cmd python3; then
			out="$(mktemp)"
			if python3 - "$rc" "$GTK_THEME_NAME" > "$out" <<'PY'
import re, sys
path, theme = sys.argv[1], sys.argv[2]
xml = open(path, encoding="utf-8").read()
def set_theme(m):
    block = m.group(0)
    if re.search(r"<name>.*?</name>", block, re.S):
        return re.sub(r"<name>.*?</name>", f"<name>{theme}</name>", block, count=1, flags=re.S)
    return block.replace("<theme>", f"<theme>\n    <name>{theme}</name>", 1)
new, n = re.subn(r"<theme>.*?</theme>", set_theme, xml, count=1, flags=re.S)
sys.stdout.write(new if n else xml)
PY
			then
				write_file "$rc" < "$out"
			else
				warn "could not set labwc theme name in $rc"
			fi
			rm -f "$out"
		fi
		;;
	wayfire)
		wf="$TARGET_HOME/.config/wayfire.ini"
		ini_set "$wf" decoration title_height 26
		ini_set "$wf" decoration active_color '\#1C1C1CFF'
		ini_set "$wf" decoration inactive_color '\#151515FF'
		;;
	*)
		warn "compositor '$COMPOSITOR' unknown; skipping window decoration colours"
		;;
esac

# --- Taskbar ---------------------------------------------------------------
# wf-panel-pi normally follows the GTK theme; these explicit colours cover the
# case where a previous Appearance Settings run pinned light ones.
panel="$TARGET_HOME/.config/wf-panel-pi.ini"
if [ -f "$panel" ]; then
	ini_set "$panel" panel background_colour '#1C1C1CFF'
	ini_set "$panel" panel foreground_colour '#E6E6E6FF'
else
	log "no wf-panel-pi.ini yet; panel will follow the GTK theme"
fi

# --- Desktop background and icon labels ------------------------------------
for items in "$TARGET_HOME"/.config/pcmanfm/*/desktop-items-0.conf; do
	[ -e "$items" ] || continue
	ini_set "$items" '*' desktop_bg '#1c1c1c'
	ini_set "$items" '*' desktop_fg '#e6e6e6'
	ini_set "$items" '*' desktop_shadow '#000000'
done

# --- Apply without a logout where the compositor supports it ---------------
if [ "$DRY_RUN" != "1" ]; then
	case "$COMPOSITOR" in
		labwc) as_user labwc --reconfigure >/dev/null 2>&1 && log "labwc reconfigured" || true ;;
	esac
	pkill -HUP -x wf-panel-pi >/dev/null 2>&1 && log "panel reloaded" || true
fi

log "some apps only pick up the new theme on next launch; log out to apply everywhere"
summary "dark-desktop"
