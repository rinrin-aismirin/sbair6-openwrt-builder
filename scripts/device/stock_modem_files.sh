# Write a tar archive of modem userspace files from a stock firmware slot to stdout. Runs on the device under the
# stock firmware; called by `./build.sh pull-modem`, which passes the slot and the paths from modem-files.lock:
#   ssh root@DEVICE 'sh -s b etc/a usr/bin/b ...' < scripts/device/stock_modem_files.sh > modem.tar
# SLOT is the slot OpenWrt will run from (normally the other one). Its stock root filesystem is mounted read-only
# under /tmp for the copy; the archive also holds MODEM_VERSION with the modem firmware version found in that
# slot's md1img and in the root filesystem's /etc/mddb. Messages go to stderr; nothing on the eMMC is written.
set -eu
[ $# -gt 1 ] || { echo "usage: sh -s SLOT PATH..." >&2; exit 2; }
SLOT=$1; shift
case "$SLOT" in a|b) ;; *) echo "abort: SLOT must be a or b" >&2; exit 2 ;; esac
[ -f /lib/upgrade/bootctrl.sh ] || {
	echo "abort: not the stock firmware; boot it first (see 'Going back to the stock firmware' in docs/install.md)" >&2
	exit 1
}
VER_RE='MOLY[A-Z0-9_]*_V[0-9]*_[0-9]*_P[0-9]*'
MD_VER=$(dd if="/dev/block/md1img_$SLOT" bs=4096 count=64 2>/dev/null | grep -a -o -m1 "$VER_RE" | head -n 1)
[ -n "$MD_VER" ] || { echo "abort: no modem version found in md1img_$SLOT" >&2; exit 1; }

RUNNING=$(sed -n 's/.*bootslot=\([ab]\).*/\1/p' /proc/cmdline)
M=/tmp/air6-pull-modem.$$
V=/tmp/air6-pull-modem-ver.$$
cleanup() {
	rm -f "$V/MODEM_VERSION"
	rmdir "$V" 2>/dev/null || true
	if [ -d "$M" ]; then umount "$M" 2>/dev/null || true; rmdir "$M" 2>/dev/null || true; fi
}
trap cleanup EXIT
if [ "$SLOT" = "$RUNNING" ]; then
	ROOT=/
else
	mkdir "$M"
	mount -t squashfs -o ro "/dev/block/rootfs_$SLOT" "$M" || { echo "abort: cannot mount rootfs_$SLOT" >&2; exit 1; }
	ROOT=$M
	[ -f "$M/lib/upgrade/bootctrl.sh" ] || {
		echo "abort: slot $SLOT does not hold the stock firmware any more; use a saved copy of its root" \
			"filesystem with './build.sh pull-modem FILE'" >&2
		exit 1
	}
fi
FS_VER=$(ls "$ROOT/etc/mddb" 2>/dev/null | grep -o -m1 "$VER_RE" | head -n 1)
for p in "$@"; do
	[ -e "$ROOT/$p" ] || [ -L "$ROOT/$p" ] || { echo "abort: $p not found in slot $SLOT" >&2; exit 1; }
done
mkdir "$V"
printf 'slot=%s\nmd1img=%s\nrootfs=%s\n' "$SLOT" "$MD_VER" "$FS_VER" > "$V/MODEM_VERSION"
# busybox tar applies only one -C: archive from ROOT and add the version file by absolute path (stored as
# tmp/air6-pull-modem-ver.PID/MODEM_VERSION).
cd "$ROOT"
tar -cf - "$@" "$V/MODEM_VERSION"
