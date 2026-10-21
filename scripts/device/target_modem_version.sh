# Print the modem firmware version (for example V26_4_P48) in md1img of the slot an install would write (the slot
# that does not run). Runs on the device under the stock firmware, read-only:
#   ssh root@DEVICE 'sh -s' < scripts/device/target_modem_version.sh
set -eu
case "$(sed -n 's/.*bootslot=\([ab]\).*/\1/p' /proc/cmdline)" in
a) T=b ;;
b) T=a ;;
*) echo "abort: bootslot not on the kernel command line" >&2; exit 1 ;;
esac
dd if="/dev/block/md1img_$T" bs=4096 count=64 2>/dev/null | grep -a -o -m1 'MOLY[A-Z0-9_]*_V[0-9]*_[0-9]*_P[0-9]*' |
	head -n 1 | grep -o 'V[0-9]*_[0-9]*_P[0-9]*$'
