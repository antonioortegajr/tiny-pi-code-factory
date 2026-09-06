#!/usr/bin/env bash
# Keep a copy of this repo on the SSD, so the next reflash does not need the
# network just to fetch the thing that sets the network up.
#
# It also carries settings.local.env across, which is gitignored and therefore
# the one piece of your setup that a git clone would not bring back.
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected

step "Mirroring the repo onto the SSD"

if [ -z "${SSD_MOUNT_POINT:-}" ] || ! mountpoint -q "$SSD_MOUNT_POINT" 2>/dev/null; then
	warn "SSD not mounted at ${SSD_MOUNT_POINT:-unset}; run 'make storage' first"
	summary "mirror"; exit 0
fi

dest="$SSD_MOUNT_POINT/my-pi5-setup"

if [ "$REPO_ROOT" = "$dest" ]; then
	skip "already running from the SSD copy"
	summary "mirror"; exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
	dry "mirror $REPO_ROOT -> $dest"
	summary "mirror"; exit 0
fi

ensure_dir "$dest"

# --delete keeps the mirror honest; state/ is machine-local and backups can be
# large, so neither belongs in it.
rsync -a --delete \
	--exclude '/state/' \
	"$REPO_ROOT/" "$dest/"
changed "mirrored to $dest"

# settings.local.env can hold a Wi-Fi password.
[ -f "$dest/settings.local.env" ] && chmod 600 "$dest/settings.local.env"
chown -R "$TARGET_USER" "$dest" 2>/dev/null || sudo chown -R "$TARGET_USER" "$dest" 2>/dev/null || true

log "after the next reflash, with no network needed:"
log "  cd $dest && make all"
summary "mirror"
