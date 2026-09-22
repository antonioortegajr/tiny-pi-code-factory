#!/usr/bin/env bash
# Replay a previously captured theme (config/captured/) onto this machine.
#
# Run this after 30-33 when you have a capture you trust: the generated defaults
# get you most of the way, this pins the exact look you signed off on.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

captured="$CONFIG_DIR/captured"

step "Applying captured theme"

if [ ! -d "$captured" ]; then
	log "no capture in config/captured/ - nothing to replay"
	log "create one on a Pi you have themed the way you want:  make capture-theme"
	summary "apply-captured"; exit 0
fi

if [ -r "$captured/theme.env" ]; then
	# shellcheck disable=SC1091
	. "$captured/theme.env"
	log "capture is from $CAPTURED_OS_CODENAME / $CAPTURED_COMPOSITOR"
	if [ "$CAPTURED_COMPOSITOR" != "$COMPOSITOR" ]; then
		warn "captured under $CAPTURED_COMPOSITOR but running $COMPOSITOR; compositor-specific files may not apply cleanly"
	fi
fi

if [ -d "$captured/home" ]; then
	while IFS= read -r src; do
		rel="${src#"$captured/home/"}"
		write_file "$TARGET_HOME/$rel" < "$src"
	done < <(find "$captured/home" -type f)
fi

if [ -d "$captured/system" ]; then
	need_sudo
	while IFS= read -r src; do
		rel="${src#"$captured/system/"}"
		write_file "/$rel" < "$src"
	done < <(find "$captured/system" -type f)
fi

if [ "$DRY_RUN" != "1" ] && [ -n "${CAPTURED_COLOR_SCHEME:-}" ] && has_cmd gsettings; then
	as_user gsettings set org.gnome.desktop.interface color-scheme "$CAPTURED_COLOR_SCHEME" 2>/dev/null || true
	[ "${CAPTURED_GTK_THEME:-unknown}" != "unknown" ] && \
		as_user gsettings set org.gnome.desktop.interface gtk-theme "$CAPTURED_GTK_THEME" 2>/dev/null || true
fi

log "log out and back in to apply everywhere"
summary "apply-captured"
