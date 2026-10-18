# Boot again into the OpenWrt image that the inactive slot already holds, from the stock firmware on either
# slot. Run on the device over SSH:
#   ssh root@DEVICE "BOOT_SHA=<sha256 of boot.img> sh -s" < scripts/device/switch_to_openwrt.sh
# Checks that boot_<target> holds that image, then makes the target preferred with success 00 and retry preset 02,
# as install_openwrt.sh does. Writes boot control only; does not touch the partitions and does not reboot.
set -eu
BOOT_SHA=${BOOT_SHA:?set BOOT_SHA to the sha256 of the boot image that the other slot holds}
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
echo "booted=$CUR target=$T"

before=$(get_bootctrl_string)
echo "bootctrl before=$before"
[ "$(field PRIORITY "$CU")" = 0f ] && [ "$(field SUCCESS "$CU")" = 01 ] && [ "$(field UP "$CU")" = 01 ] &&
	[ "$(field PRIORITY "$TU")" = 0e ] || { echo "abort: unexpected bootctrl $before"; exit 1; }
[ "$(sha256sum < "/dev/block/boot_$T" | cut -d' ' -f1)" = "$BOOT_SHA" ] ||
	{ echo "abort: boot_$T is not the expected image"; exit 1; }

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
