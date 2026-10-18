# Install an OpenWrt image into the inactive slot of an Air 6 running the stock firmware from either slot.
# Run on the device over SSH:
#   ssh root@DEVICE "BOOT_SHA=<sha256 of boot.img> ROOTFS_SHA=<sha256 of rootfs.img> sh -s" < scripts/device/install_openwrt.sh
# Prerequisite: /tmp/air6-boot.img and /tmp/air6-rootfs.img uploaded to the device.
# The active slot comes from bootslot= on the kernel command line; only the other slot ("target") is written.
# After writing and verifying boot_<target> and rootfs_<target>, the vendor change_slot_info makes the target
# preferred with success 00, and its retry preset is set to 02. The preloader increments the retry count at every
# boot of the target and switches to the other slot when it reads 4: the target boots twice (retry 3 and 4) and the
# third boot goes to the stock slot (observed on the device). Does not reboot.
# Prints the boot control bytes before and after, and a command that restores the previous bytes.
set -eu
BOOT_SHA=${BOOT_SHA:?set BOOT_SHA to the sha256 of boot.img}
ROOTFS_SHA=${ROOTFS_SHA:?set ROOTFS_SHA to the sha256 of rootfs.img}
[ -f /lib/upgrade/bootctrl.sh ] || { echo "abort: not the stock firmware (no /lib/upgrade/bootctrl.sh)"; exit 1; }
. /lib/upgrade/common.sh 2>/dev/null || true
. /lib/upgrade/platform.sh 2>/dev/null || true
. /lib/upgrade/bootctrl.sh
FLASH_TYPE=$(get_flash_type)

CUR=$(sed -n 's/.*bootslot=\([ab]\).*/\1/p' /proc/cmdline)
case "$CUR" in
a) T=b ;;
b) T=a ;;
*) echo "abort: bootslot not on the kernel command line"; exit 1 ;;
esac
CU=$(echo "$CUR" | tr ab AB) TU=$(echo "$T" | tr ab AB)
# field NAME SLOT: one boot control byte (NAME is PRIORITY, TRY, SUCCESS or UP) as two hex digits
field() { eval "get_bootctrl \$BOOTCTRL_OFFSET_$1_$2 1"; }
part_size() { echo $(( $(cat "/sys/class/block/$(basename "$(readlink -f "$1")")/size") * 512 )); }
BOOT_DEV=/dev/block/boot_$T ROOTFS_DEV=/dev/block/rootfs_$T
echo "booted=$CUR target=$T"

before=$(get_bootctrl_string)
echo "bootctrl before=$before"
[ "$(field PRIORITY "$CU")" = 0f ] && [ "$(field SUCCESS "$CU")" = 01 ] && [ "$(field UP "$CU")" = 01 ] &&
	[ "$(field PRIORITY "$TU")" = 0e ] || { echo "abort: unexpected bootctrl $before"; exit 1; }
[ -b "$BOOT_DEV" ] && [ -b "$ROOTFS_DEV" ] || { echo "abort: $BOOT_DEV or $ROOTFS_DEV missing"; exit 1; }
! grep -q "^$(readlink -f "$ROOTFS_DEV") " /proc/mounts || { echo "abort: $ROOTFS_DEV is mounted"; exit 1; }
[ "$(sha256sum < /tmp/air6-boot.img | cut -d' ' -f1)" = "$BOOT_SHA" ] || { echo "abort: boot image hash"; exit 1; }
[ "$(sha256sum < /tmp/air6-rootfs.img | cut -d' ' -f1)" = "$ROOTFS_SHA" ] || { echo "abort: rootfs image hash"; exit 1; }
[ "$(wc -c < /tmp/air6-boot.img)" = "$(part_size "$BOOT_DEV")" ] || { echo "abort: boot size"; exit 1; }
[ "$(wc -c < /tmp/air6-rootfs.img)" = "$(part_size "$ROOTFS_DEV")" ] || { echo "abort: rootfs size"; exit 1; }

dd if=/tmp/air6-boot.img of="$BOOT_DEV" bs=1048576 2>&1 | tail -1
dd if=/tmp/air6-rootfs.img of="$ROOTFS_DEV" bs=1048576 2>&1 | tail -1
sync
echo 3 > /proc/sys/vm/drop_caches
[ "$(sha256sum < "$BOOT_DEV" | cut -d' ' -f1)" = "$BOOT_SHA" ] || { echo "WRITE VERIFY FAILED (boot_$T)"; exit 2; }
[ "$(sha256sum < "$ROOTFS_DEV" | cut -d' ' -f1)" = "$ROOTFS_SHA" ] || { echo "WRITE VERIFY FAILED (rootfs_$T)"; exit 2; }
echo "boot_$T and rootfs_$T written and verified"

change_slot_info "_$CUR" 1 >/dev/null
eval "set_bootctrl \$BOOTCTRL_OFFSET_TRY_$TU \\\\x02"
sync
echo "bootctrl after=$(get_bootctrl_string)"
echo "rollback (run on the unit before rebooting): . /lib/upgrade/common.sh; . /lib/upgrade/platform.sh;" \
	". /lib/upgrade/bootctrl.sh; FLASH_TYPE=\$(get_flash_type); write_bootctrl_string '$(echo "$before" | sed 's/../\\x&/g')'"
[ "$(field PRIORITY "$CU")" = 0e ] && [ "$(field SUCCESS "$CU")" = 01 ] &&
	[ "$(field PRIORITY "$TU")" = 0f ] && [ "$(field TRY "$TU")" = 02 ] &&
	[ "$(field SUCCESS "$TU")" = 00 ] && [ "$(field UP "$TU")" = 01 ] || { echo "UNEXPECTED bootctrl"; exit 3; }
echo "slot $T preferred, retry preset 02"
