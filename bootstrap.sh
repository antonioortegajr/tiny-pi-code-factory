#!/usr/bin/env bash
# One command to run on a freshly flashed Pi:
#
#   curl -fsSL https://raw.githubusercontent.com/antonioortegajr/tiny-pi-code-factory/main/bootstrap.sh | bash
#
# Finds the repo the cheapest way it can - a copy on the SSD first, then a git
# clone - and hands over to make.
#
# Environment:
#   REPO_URL    override the clone URL
#   GH_TOKEN    personal access token, for a private repo
#   SSD_REPO    where to look for an existing copy (default /mnt/ssd/tiny-pi-code-factory)
#
# The token is also read from a file, so it never has to be typed on the Pi:
#   /boot/firmware/gh-token   drop this on the boot partition from your Mac
#                             after imaging, before first boot
#   ~/.gh-token
#   /mnt/ssd/.gh-token        survives a reflash with the rest of the SSD
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/antonioortegajr/tiny-pi-code-factory.git}"
CLONE_DIR="${CLONE_DIR:-$HOME/tiny-pi-code-factory}"
SSD_REPO="${SSD_REPO:-/mnt/ssd/tiny-pi-code-factory}"
TARGET="${1:-all}"

say()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "Run this as your normal user, not root - it needs to know whose desktop to theme."

# --- the repo may already be on the SSD, which survives a reflash ----------
# Checked before the network, because it is the one path that does not need one.
if [ -d "$SSD_REPO/.git" ] || [ -f "$SSD_REPO/Makefile" ]; then
	say "found an existing copy on the SSD: $SSD_REPO"
	cd "$SSD_REPO"
	exec make "$TARGET"
fi

# Lite images are minimal; do not assume either of these is present.
missing=""
command -v git  >/dev/null 2>&1 || missing="$missing git"
command -v curl >/dev/null 2>&1 || missing="$missing curl"
if [ -n "$missing" ]; then
	say "installing:$missing"
	sudo apt-get update -qq
	# shellcheck disable=SC2086
	sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $missing
fi

# --- otherwise we need the network ----------------------------------------
if ! curl -fsS --max-time 10 -o /dev/null https://github.com 2>/dev/null; then
	warn "cannot reach github.com"
	cat >&2 <<'MSG'

  Get online first, then rerun this. Quickest options:

    - plug in an ethernet cable
    - join Wi-Fi:
        sudo nmcli device wifi list
        sudo nmcli device wifi connect '<SSID>' password '<password>'

  Next time, set Wi-Fi in Raspberry Pi Imager before writing the image and
  the Pi comes up online by itself.

MSG
	exit 1
fi

# Find a token without making anyone type one. The boot partition is FAT and
# mounts on a Mac, so the file can be dropped there straight after imaging.
if [ -z "${GH_TOKEN:-}" ]; then
	for f in /boot/firmware/gh-token "$HOME/.gh-token" /mnt/ssd/.gh-token; do
		if [ -r "$f" ]; then
			GH_TOKEN="$(tr -d " \t\r\n" < "$f")"
			[ -n "$GH_TOKEN" ] && say "using the token in $f" && break
		fi
	done
fi

# A token, if given, is used for this clone only - never written into the
# repo's remote, where it would sit in .git/config in the clear.
clone_url="$REPO_URL"
if [ -n "${GH_TOKEN:-}" ]; then
	clone_url="${REPO_URL/https:\/\//https://$GH_TOKEN@}"
fi

if [ -d "$CLONE_DIR/.git" ]; then
	say "updating $CLONE_DIR"
	git -C "$CLONE_DIR" pull --ff-only
else
	say "cloning into $CLONE_DIR"
	if ! git clone --depth 1 "$clone_url" "$CLONE_DIR"; then
		die "clone failed. If the repo is private, rerun with: GH_TOKEN=<token> bash bootstrap.sh"
	fi
	[ -n "${GH_TOKEN:-}" ] && git -C "$CLONE_DIR" remote set-url origin "$REPO_URL"
fi

say "running: make $TARGET"
cd "$CLONE_DIR"
exec make "$TARGET"
