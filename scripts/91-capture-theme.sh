#!/usr/bin/env bash
# Snapshot the theme files as they are on this Pi right now, into config/captured/.
#
# Why this exists: the exact key names the Pi desktop uses move between releases.
# Rather than guessing forever, set the look you want with Appearance Settings,
# run this, and commit the result - 34-apply-captured-theme.sh then reproduces
# exactly that on the next flash.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
# shellcheck source=../lib/theme-files.sh
. "$REPO_ROOT/lib/theme-files.sh"
load_detected

step "Capturing current theme into config/captured/"

captured="$CONFIG_DIR/captured"
count=0

for rel in "${HOME_THEME_FILES[@]}"; do
	src="$TARGET_HOME/$rel"
	[ -f "$src" ] || continue
	write_file "$captured/home/$rel" < "$src"
	count=$((count + 1))
done

for abs in "${SYSTEM_THEME_FILES[@]}"; do
	[ -f "$abs" ] || continue
	tmp="$(mktemp)"
	if [ -r "$abs" ]; then cat "$abs" > "$tmp"; else sudo cat "$abs" > "$tmp"; fi
	write_file "$captured/system/${abs#/}" < "$tmp"
	rm -f "$tmp"
	count=$((count + 1))
done

# Which GTK theme is actually in effect, so replay does not have to re-detect.
write_file "$captured/theme.env" <<ENV
# Captured on $(date -Iseconds) from $OS_PRETTY ($COMPOSITOR)
CAPTURED_OS_CODENAME="$OS_CODENAME"
CAPTURED_COMPOSITOR="$COMPOSITOR"
CAPTURED_GTK_THEME="$(as_user gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'" || echo unknown)"
CAPTURED_COLOR_SCHEME="$(as_user gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | tr -d "'" || echo unknown)"
ENV

log "captured $count file(s)"
log "review with 'git diff config/captured', then commit"
summary "capture-theme"
