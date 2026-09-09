#!/usr/bin/env bash
# Environment detection and privilege helpers.

# Resolve the repo root from this file's location, so scripts work from any cwd.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="$REPO_ROOT/state"
CONFIG_DIR="$REPO_ROOT/config"
DRY_RUN="${DRY_RUN:-0}"

# One timestamp per run, so all backups from a single invocation land together.
RUN_TS="${RUN_TS:-$(date +%Y%m%d-%H%M%S)}"
BACKUP_DIR="$STATE_DIR/backups/$RUN_TS"

# The human whose ~/.config we are theming. Survives being run under sudo.
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
	TARGET_USER="$SUDO_USER"
else
	TARGET_USER="$(id -un)"
fi
TARGET_HOME="$( { getent passwd "$TARGET_USER" 2>/dev/null || true; } | cut -d: -f6 )"
[ -n "$TARGET_HOME" ] || TARGET_HOME="$HOME"

has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Run a command, honouring DRY_RUN.
run() {
	if [ "$DRY_RUN" = "1" ]; then dry "run: $*"; return 0; fi
	"$@"
}

# Same, but the command is expected to change something worth counting.
run_change() {
	if [ "$DRY_RUN" = "1" ]; then dry "run: $*"; return 0; fi
	"$@" && changed "$*"
}

# Prime the sudo timestamp up front so a long run does not stall on a password
# prompt buried in the middle of it.
need_sudo() {
	# A dry run makes no changes, so it must never stop to ask for a password.
	if [ "$DRY_RUN" = "1" ]; then dry "authenticate with sudo"; return 0; fi
	[ "$(id -u)" -eq 0 ] && return 0
	has_cmd sudo || die "sudo not found and not running as root"
	sudo -n true 2>/dev/null && return 0
	log "sudo password needed for system-level changes"
	sudo -v || die "sudo authentication failed"
}

# Echo the sudo prefix needed to write to a path (empty when already writable).
priv_for() {
	local target="$1" dir
	dir="$(dirname "$target")"
	if [ -e "$target" ]; then
		[ -w "$target" ] && return 0
	elif [ -w "$dir" ]; then
		return 0
	fi
	[ "$(id -u)" -eq 0 ] && return 0
	echo "sudo"
}

# --- detection -------------------------------------------------------------

pi_model() {
	{ tr -d '\0' < /proc/device-tree/model; } 2>/dev/null || echo "unknown"
}

os_codename() {
	# shellcheck disable=SC1091
	{ . /etc/os-release && echo "${VERSION_CODENAME:-unknown}"; } 2>/dev/null || echo "unknown"
}

# labwc (Trixie default) vs wayfire (Bookworm default) vs X11/unknown.
detect_compositor() {
	if pgrep -x labwc >/dev/null 2>&1; then echo labwc; return; fi
	if pgrep -x wayfire >/dev/null 2>&1; then echo wayfire; return; fi
	# Not running one right now (e.g. over SSH) - fall back to what is installed,
	# preferring the newer compositor when both are present.
	if has_cmd labwc; then echo labwc; return; fi
	if has_cmd wayfire; then echo wayfire; return; fi
	echo none
}

# Load state/detected.env if 00-preflight has run; otherwise detect inline so
# every script stays independently runnable.
load_detected() {
	if [ -r "$STATE_DIR/detected.env" ]; then
		# shellcheck disable=SC1091
		. "$STATE_DIR/detected.env"
	fi
	# Every field detected.env can carry needs a default here, or a script run
	# before preflight dies on set -u rather than degrading.
	: "${OS_CODENAME:=$(os_codename)}"
	: "${OS_PRETTY:=$OS_CODENAME}"
	: "${COMPOSITOR:=$(detect_compositor)}"
	: "${MODEL:=$(pi_model)}"
	: "${ARCH:=$(uname -m)}"
	: "${KERNEL:=$(uname -r)}"
	: "${HAS_DESKTOP:=0}"
	: "${ROOT_SRC:=$(findmnt -no SOURCE / 2>/dev/null || echo unknown)}"
	: "${ROOT_DISK:=}"
	: "${BOOT_SRC:=$(findmnt -no SOURCE /boot/firmware 2>/dev/null || echo none)}"
	: "${HAS_NVME:=0}"
	: "${EXTRA_DISK:=}"
	: "${EXTRA_DISK_TRAN:=}"
	export OS_CODENAME OS_PRETTY COMPOSITOR MODEL ARCH KERNEL HAS_DESKTOP \
	       ROOT_SRC ROOT_DISK BOOT_SRC HAS_NVME EXTRA_DISK EXTRA_DISK_TRAN
}

# Guard for scripts that only make sense on the Pi itself.
require_pi() {
	case "$(pi_model)" in
		*"Raspberry Pi"*) return 0 ;;
	esac
	if [ "${ALLOW_NON_PI:-0}" = "1" ]; then
		warn "not a Raspberry Pi, continuing because ALLOW_NON_PI=1"
		return 0
	fi
	die "this script targets a Raspberry Pi. Set ALLOW_NON_PI=1 to override."
}

# Run a command as the target user, even when the script itself was invoked with
# sudo. Needed for gsettings/dconf, which write into that user's session.
as_user() {
	if [ "$(id -un)" = "$TARGET_USER" ]; then
		"$@"
	else
		sudo -u "$TARGET_USER" \
			env XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
			    HOME="$TARGET_HOME" "$@"
	fi
}
