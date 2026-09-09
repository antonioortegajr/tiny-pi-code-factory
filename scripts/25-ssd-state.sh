#!/usr/bin/env bash
# Put the expensive, slow-to-rebuild state on the SSD so an OS reflash does not
# take it with it.
#
# What survives a reflash after this runs:
#   - Docker images and volumes (a container carries its own userland, so it does
#     not care that the host OS changed underneath it)
#   - Ollama models
#   - whatever you bind-mount from the SSD into your home directory
#
# What does not, and does not need to: apt packages and binaries. Those are
# minutes to reinstall - see 'make restore-packages'.
#
#   --migrate-docker   move an existing /var/lib/docker onto the SSD
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected

MIGRATE_DOCKER=0
for arg in "$@"; do
	case "$arg" in
		--migrate-docker) MIGRATE_DOCKER=1 ;;
		*) die "unknown argument: $arg" ;;
	esac
done

step "Persistent state on the SSD"

if [ "${PERSIST_ON_SSD:-1}" != "1" ]; then
	log "PERSIST_ON_SSD=0, nothing to do"
	summary "ssd-state"; exit 0
fi

if [ -z "${SSD_MOUNT_POINT:-}" ]; then
	log "SSD_MOUNT_POINT is unset; nothing to do"
	summary "ssd-state"; exit 0
fi

if ! mountpoint -q "$SSD_MOUNT_POINT" 2>/dev/null; then
	warn "$SSD_MOUNT_POINT is not mounted - run 'make storage' first"
	log "skipping: putting state here while the SSD is absent would write it to the boot drive"
	summary "ssd-state"; exit 0
fi

need_sudo
log "using $SSD_MOUNT_POINT"

# --- directories -----------------------------------------------------------
for d in ${SSD_STATE_DIRS:-docker ollama projects}; do
	ensure_dir "$SSD_MOUNT_POINT/$d"
done

# --- Docker ----------------------------------------------------------------
# Written whether or not Docker is installed yet: if apps/ installs it later it
# picks this up on first start, and no migration is ever needed.
docker_root="$SSD_MOUNT_POINT/docker"
before="$CHANGE_COUNT"
json_merge /etc/docker/daemon.json "{\"data-root\": \"$docker_root\"}"
docker_root_changed=$([ "$CHANGE_COUNT" != "$before" ] && echo 1 || echo 0)

if has_cmd docker; then
	# -n on both: these are read-only probes and must never sit on a password
	# prompt, and neither must trip pipefail when docker is not running.
	current_root="$(sudo -n docker info -f '{{.DockerRootDir}}' 2>/dev/null || echo unknown)"
	existing_images="$( { sudo -n docker images -q 2>/dev/null || true; } | wc -l | tr -d ' ')"

	if [ "$current_root" = "$docker_root" ]; then
		skip "docker already stores data on the SSD"
	elif [ "$existing_images" != "0" ] && [ "$MIGRATE_DOCKER" != "1" ]; then
		# Restarting now would leave the old images stranded in /var/lib/docker,
		# invisible but still eating the boot drive.
		warn "docker has $existing_images image(s) in $current_root"
		log "not restarting docker: that would hide them without freeing the space"
		log "to move them across:  make ssd-state ARGS=--migrate-docker"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "restart docker onto $docker_root"
	elif [ "$MIGRATE_DOCKER" = "1" ] && [ "$existing_images" != "0" ]; then
		log "stopping docker to copy $current_root -> $docker_root"
		sudo systemctl stop docker docker.socket 2>/dev/null || true
		sudo rsync -aHAX --info=progress2 "$current_root/" "$docker_root/"
		sudo systemctl start docker
		changed "migrated docker data to the SSD"
		log "old data is still in $current_root - delete it once you are happy:"
		log "  sudo rm -rf $current_root"
	else
		sudo systemctl restart docker 2>/dev/null && changed "docker now stores data on the SSD" \
			|| warn "could not restart docker"
	fi
elif [ "$docker_root_changed" = "1" ]; then
	log "docker not installed yet; it will use $docker_root when it is"
fi

# --- Start-up ordering -----------------------------------------------------
# Without this, docker and ollama can start before the SSD is mounted, find
# their data directory missing, and quietly recreate it on the boot drive.
for unit in docker ollama; do
	systemctl list-unit-files "$unit.service" >/dev/null 2>&1 || continue
	write_file "/etc/systemd/system/$unit.service.d/15-ssd-mount.conf" <<UNIT
# Managed by my-pi5-setup (scripts/25-ssd-state.sh)
[Unit]
RequiresMountsFor=$SSD_MOUNT_POINT
UNIT
done
[ "$DRY_RUN" = "1" ] || sudo systemctl daemon-reload

# --- Bind mounts into the home directory -----------------------------------
# Selective, not all of /home: dragging a whole home directory across an OS
# change brings stale dotfiles with it, which is how a fresh install stops
# being fresh.
# Permissions have to survive the trip. A FAT or NTFS SSD cannot hold the 0600
# that ssh insists on, and would lock key auth out entirely.
ssd_fstype="$(findmnt -no FSTYPE "$SSD_MOUNT_POINT" 2>/dev/null || echo unknown)"

for spec in ${SSD_BIND_MOUNTS:-}; do
	src="$SSD_MOUNT_POINT/${spec%%:*}"
	dest="${spec#*:}"
	[ "$src" = "$dest" ] && { warn "malformed SSD_BIND_MOUNTS entry: $spec"; continue; }

	case "$dest:$ssd_fstype" in
		*/.ssh:vfat|*/.ssh:exfat|*/.ssh:ntfs*|*/.ssh:msdos)
			warn "the SSD is $ssd_fstype, which cannot store unix permissions"
			log "ssh would reject the keys; skipping the .ssh bind mount"
			continue
			;;
	esac

	ensure_dir "$src"
	ensure_dir "$dest"
	[ "$DRY_RUN" = "1" ] || sudo chown "$TARGET_USER" "$src" "$dest" 2>/dev/null || true

	# A fresh image already has content here in the common case: Raspberry Pi
	# Imager writes ~/.ssh/authorized_keys on first boot. Seed the SSD from it
	# rather than refusing, so the first run works without hand-holding.
	src_has="$(ls -A "$src" 2>/dev/null || true)"
	dest_has="$(ls -A "$dest" 2>/dev/null || true)"

	if ! mountpoint -q "$dest" 2>/dev/null && [ -n "$dest_has" ]; then
		if [ -z "$src_has" ]; then
			if [ "$DRY_RUN" = "1" ]; then
				dry "seed $src from the existing $dest"
			else
				sudo rsync -aHAX "$dest/" "$src/"
				sudo chown -R "$TARGET_USER" "$src"
				changed "seeded $src from $dest"
			fi
		else
			# Both sides hold data and we cannot know which is authoritative.
			warn "$dest and $src both have content; not bind-mounting"
			log "reconcile them by hand, then rerun"
			continue
		fi
	fi

	ensure_line /etc/fstab \
		"$src	$dest	none	bind,nofail	0	0" \
		"^$src[[:space:]]"

	if [ "$DRY_RUN" != "1" ] && ! mountpoint -q "$dest" 2>/dev/null; then
		sudo systemctl daemon-reload
		sudo mount "$dest" && changed "bind-mounted $dest -> $src" \
			|| warn "could not bind-mount $dest"
	fi

	# ssh refuses to use a directory with loose permissions, and the seeding
	# above ran as root, so fix them up every time.
	case "$dest" in
		*/.ssh)
			if [ "$DRY_RUN" != "1" ]; then
				sudo chown -R "$TARGET_USER" "$dest"
				sudo chmod 700 "$dest"
				sudo find "$dest" -type f -exec chmod 600 {} + 2>/dev/null || true
				sudo chmod 644 "$dest"/*.pub 2>/dev/null || true
			fi
			;;
	esac
done

log "state that now lives on the SSD survives the next reflash"
summary "ssd-state"
