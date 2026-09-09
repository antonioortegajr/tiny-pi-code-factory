#!/usr/bin/env bash
# Boot order, the SSD on the HAT, swap and trim.
#
# This script never formats or partitions anything. If the SSD has no filesystem
# it says so and stops there, because guessing is not worth the risk.
#
#   --fix-boot-order   also rewrite the EEPROM boot order (off by default)
. "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
load_detected
require_pi
need_sudo

FIX_BOOT_ORDER=0
for arg in "$@"; do
	case "$arg" in
		--fix-boot-order) FIX_BOOT_ORDER=1 ;;
		*) die "unknown argument: $arg" ;;
	esac
done

step "Boot order"

if has_cmd rpi-eeprom-config; then
	current_order="$( { sudo rpi-eeprom-config 2>/dev/null || true; } | sed -n 's/^BOOT_ORDER=//p' | head -n1)"
	log "current BOOT_ORDER: ${current_order:-unset}   (right-to-left: 1=SD 4=USB 6=NVMe f=restart)"
	log "booted from:        $ROOT_SRC"

	if [ "$FIX_BOOT_ORDER" != "1" ]; then
		if [ "$current_order" != "$BOOT_ORDER_DESIRED" ]; then
			log "differs from BOOT_ORDER_DESIRED=$BOOT_ORDER_DESIRED"
			log "the Pi is booting fine as-is, so nothing was changed."
			log "to write it anyway: make storage ARGS=--fix-boot-order"
		else
			skip "boot order already $BOOT_ORDER_DESIRED"
		fi
	elif [ "$current_order" = "$BOOT_ORDER_DESIRED" ]; then
		skip "boot order already $BOOT_ORDER_DESIRED"
	elif [ "$DRY_RUN" = "1" ]; then
		dry "set BOOT_ORDER=$BOOT_ORDER_DESIRED in the EEPROM"
	else
		printf '\n  About to write BOOT_ORDER=%s to the Pi EEPROM.\n' "$BOOT_ORDER_DESIRED"
		printf '  A wrong value here can leave the Pi unable to boot.\n'
		read -r -p "  Type 'yes' to continue: " reply
		if [ "$reply" = "yes" ]; then
			tmp="$(mktemp)"
			sudo rpi-eeprom-config > "$tmp"
			ensure_line "$tmp" "BOOT_ORDER=$BOOT_ORDER_DESIRED" '^BOOT_ORDER='
			sudo rpi-eeprom-config --apply "$tmp"
			rm -f "$tmp"
			changed "EEPROM boot order (takes effect on next boot)"
		else
			log "left the EEPROM alone"
		fi
	fi
else
	skip "rpi-eeprom-config not available"
fi

step "PCIe / NVMe"

if [ "${HAS_NVME:-0}" = "1" ]; then
	# The Pi 5 negotiates Gen 2 by default; Gen 3 is faster but not certified, so
	# it is opt-in through settings and easy to comment out if the SSD misbehaves.
	if [ "${PCIE_GEN3:-0}" = "1" ]; then
		ensure_line /boot/firmware/config.txt 'dtparam=pciex1_gen=3' '^#\?dtparam=pciex1_gen='
		log "PCIe Gen 3 requested; reboot to apply"
	else
		skip "PCIe Gen 3 not enabled (set PCIE_GEN3=1 in settings.local.env)"
	fi
else
	skip "no NVMe device present"
fi

step "SSD on the HAT"

if [ -z "${EXTRA_DISK:-}" ]; then
	log "no second disk detected; nothing to mount"
elif [ -z "$SSD_MOUNT_POINT" ]; then
	skip "SSD_MOUNT_POINT is empty, mounting disabled"
else
	# First filesystem on that disk. The disk's own line is included rather than
	# skipped, because a single-purpose data disk is often formatted whole with
	# no partition table at all - that is a perfectly good ext4 to mount.
	part_uuid=""; part_fs=""; part_name=""
	while read -r name fstype uuid; do
		[ -n "$fstype" ] && [ -n "$uuid" ] || continue
		case "$fstype" in vfat|swap) continue ;; esac
		part_name="$name"; part_fs="$fstype"; part_uuid="$uuid"
		break
	done < <(lsblk -nr -o NAME,FSTYPE,UUID "/dev/$EXTRA_DISK" 2>/dev/null)

	if [ -z "$part_uuid" ]; then
		warn "/dev/$EXTRA_DISK has no filesystem"
		log "size: $(lsblk -dn -o SIZE "/dev/$EXTRA_DISK" 2>/dev/null | tr -d ' ')" \
			"  model: $(lsblk -dn -o MODEL "/dev/$EXTRA_DISK" 2>/dev/null | sed 's/  */ /g')"
		log ""
		log "This script will not format a disk for you. Check the device name is"
		log "the SSD and not something you care about, then run it yourself:"
		log ""
		log "  sudo mkfs.ext4 -L ssd /dev/$EXTRA_DISK"
		log ""
		log "That formats the whole device, which is right for a data-only disk."
		log "then rerun: make storage"
	else
		log "using /dev/$part_name ($part_fs, UUID=$part_uuid)"
		ensure_dir "$SSD_MOUNT_POINT"
		ensure_line /etc/fstab \
			"UUID=$part_uuid	$SSD_MOUNT_POINT	$part_fs	$SSD_MOUNT_OPTS	0	2" \
			"^UUID=$part_uuid[[:space:]]"
		if [ "$DRY_RUN" != "1" ]; then
			sudo systemctl daemon-reload
			if mountpoint -q "$SSD_MOUNT_POINT"; then
				skip "$SSD_MOUNT_POINT already mounted"
			else
				sudo mount "$SSD_MOUNT_POINT" && changed "mounted $SSD_MOUNT_POINT" \
					|| warn "mount $SSD_MOUNT_POINT failed; check /etc/fstab"
			fi
		fi
	fi
fi

step "Trim and swap"

if systemctl list-unit-files fstrim.timer >/dev/null 2>&1; then
	if systemctl is-enabled --quiet fstrim.timer 2>/dev/null; then
		skip "fstrim.timer already enabled"
	else
		run_change sudo systemctl enable --now fstrim.timer
	fi
fi

if [ "${ZRAM_PERCENT:-0}" != "0" ]; then
	apt_install_optional zram-tools
	if pkg_installed zram-tools; then
		ensure_line /etc/default/zramswap "PERCENT=$ZRAM_PERCENT" '^#\?PERCENT='
		[ "$DRY_RUN" = "1" ] || sudo systemctl restart zramswap 2>/dev/null || true
	fi
else
	skip "zram disabled (ZRAM_PERCENT=0)"
fi

summary "storage"
