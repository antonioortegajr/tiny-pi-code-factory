#!/usr/bin/env bash
# Dark theme for the applications that do not follow the GTK theme on their own.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected

step "Dark theme: applications"

# --- VS Code / Code - OSS / VSCodium ---------------------------------------
# Merged into settings.json rather than written over it, so keybindings and
# extension settings survive.
for dir in "Code" "Code - OSS" "VSCodium"; do
	settings="$TARGET_HOME/.config/$dir/User/settings.json"
	[ -d "$TARGET_HOME/.config/$dir" ] || continue
	json_merge "$settings" '{
		"workbench.colorTheme": "Default Dark Modern",
		"workbench.preferredDarkColorTheme": "Default Dark Modern",
		"window.autoDetectColorScheme": false
	}'
done

# --- Chromium --------------------------------------------------------------
if has_cmd chromium || has_cmd chromium-browser || [ -d /etc/chromium.d ]; then
	install_config chromium.d/99-dark-mode /etc/chromium.d/99-dark-mode
else
	skip "chromium not installed"
fi

# --- Firefox ---------------------------------------------------------------
# Firefox follows the GTK theme for its own chrome, but renders pages light
# unless told otherwise. user.js applies per profile and is easy to delete.
ff_profiles=("$TARGET_HOME"/.mozilla/firefox/*.default* "$TARGET_HOME"/snap/firefox/common/.mozilla/firefox/*.default*)
ff_found=0
for prof in "${ff_profiles[@]}"; do
	[ -d "$prof" ] || continue
	ff_found=1
	write_file "$prof/user.js" <<'JS'
// Managed by my-pi5-setup (scripts/32-dark-apps.sh)
user_pref("ui.systemUsesDarkTheme", 1);
user_pref("layout.css.prefers-color-scheme.content-override", 0);
user_pref("browser.theme.content-theme", 0);
user_pref("browser.theme.toolbar-theme", 0);
JS
done
[ "$ff_found" = 0 ] && skip "no firefox profile found (start it once, then rerun)"

# --- Thonny ----------------------------------------------------------------
thonny="$TARGET_HOME/.config/Thonny/configuration.ini"
if has_cmd thonny || [ -f "$thonny" ]; then
	ini_set "$thonny" view ui_theme 'Clean Dark'
	ini_set "$thonny" view syntax_theme 'Default Dark'
else
	skip "thonny not installed"
fi

# --- Geany -----------------------------------------------------------------
if has_cmd geany; then
	scheme=""
	for candidate in dark.conf darkness.conf; do
		if [ -f "/usr/share/geany/colorschemes/$candidate" ]; then scheme="$candidate"; break; fi
	done
	if [ -n "$scheme" ]; then
		ini_set "$TARGET_HOME/.config/geany/geany.conf" geany color_scheme "$scheme"
	else
		warn "no dark geany colorscheme installed (try: apt install geany-colorschemes)"
	fi
else
	skip "geany not installed"
fi

summary "dark-apps"
