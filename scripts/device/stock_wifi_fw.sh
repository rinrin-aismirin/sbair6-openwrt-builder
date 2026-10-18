# Write a tar archive of the given files of the running stock firmware to stdout. Runs on the device; called by
# `./build.sh pull-fw`, which passes the paths from stock-firmware.lock:
#   ssh root@DEVICE 'sh -s /lib/firmware/A.bin /lib/firmware/B.bin' < scripts/device/stock_wifi_fw.sh > fw.tar
# Stock firmware only: the files are read as the stock firmware sees them (root filesystem and its overlay).
# Messages go to stderr; nothing on the device is written.
set -eu
[ $# -gt 0 ] || { echo "usage: sh -s PATH..." >&2; exit 2; }
[ -f /lib/upgrade/bootctrl.sh ] || {
	echo "abort: not the stock firmware; boot it first (see 'Going back to the stock firmware' in docs/install.md)" >&2
	exit 1
}
for p in "$@"; do
	[ -f "$p" ] || { echo "abort: $p not found" >&2; exit 1; }
done
cd /
tar -cf - $(for p in "$@"; do echo "${p#/}"; done)
