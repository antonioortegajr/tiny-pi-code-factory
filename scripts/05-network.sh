#!/usr/bin/env bash
# Make sure the Pi can actually reach the internet before anything tries to
# download. Everything after this point - apt, ollama, docker - fails in a
# confusing way without it, so fail here instead, with something actionable.
#
# Wi-Fi credentials belong in Raspberry Pi Imager, which bakes them into the
# image before first boot. WIFI_SSID/WIFI_PSK in settings.local.env are the
# fallback for when that was not done.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected

step "Network"

online() {
	# DNS plus TLS to the host we actually need, rather than pinging 8.8.8.8 and
	# calling a broken resolver "online".
	curl -fsS --max-time "${NET_TIMEOUT:-10}" -o /dev/null https://github.com 2>/dev/null
}

if online; then
	log "github.com reachable"
	summary "network"; exit 0
fi

warn "cannot reach github.com"

# --- try to join a network -------------------------------------------------
if [ -n "${WIFI_SSID:-}" ] && has_cmd nmcli; then
	if [ "$DRY_RUN" = "1" ]; then
		dry "nmcli connect to $WIFI_SSID"
	else
		need_sudo
		log "joining Wi-Fi network '$WIFI_SSID'"
		if [ -n "${WIFI_PSK:-}" ]; then
			sudo nmcli device wifi connect "$WIFI_SSID" password "$WIFI_PSK" >/dev/null 2>&1 \
				|| warn "could not join $WIFI_SSID"
		else
			sudo nmcli device wifi connect "$WIFI_SSID" >/dev/null 2>&1 \
				|| warn "could not join $WIFI_SSID"
		fi
	fi
fi

# --- wait, in case the link is just still coming up ------------------------
if [ "$DRY_RUN" != "1" ]; then
	waited=0
	limit="${NET_WAIT:-30}"
	while [ "$waited" -lt "$limit" ]; do
		if online; then
			changed "network is up after ${waited}s"
			summary "network"; exit 0
		fi
		sleep 3
		waited=$((waited + 3))
	done
fi

# --- give up with instructions, not a stack trace --------------------------
printf '\n'
log "still offline. Wi-Fi is normally baked in by Raspberry Pi Imager, so the"
log "likely causes are a typo in the SSID or password, or the AP being out of range."
log ""
log "  check what the image was given:"
log "    nmcli connection show"
log "  see what is in range:"
log "    sudo nmcli device wifi list"
log "  join by hand:"
log "    sudo nmcli device wifi connect '<SSID>' password '<password>'"
log "  or plug in an ethernet cable and rerun"
printf '\n'

if [ "${NET_REQUIRED:-1}" = "1" ]; then
	die "no network. Set NET_REQUIRED=0 to continue anyway (apt and app installs will fail)."
fi

warn "continuing offline because NET_REQUIRED=0"
summary "network"
