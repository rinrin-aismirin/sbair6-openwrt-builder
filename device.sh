#!/bin/bash
# Host entry point for working with the Air 6 over SSH (ssh command from $AIR6_SSH, default "ssh").
#   ./device.sh status DEVICE           show the booted slot and the boot control bytes
#   ./device.sh install DEVICE STAMP    (stock firmware) upload out/STAMP and install it into the other slot
#   ./device.sh reboot DEVICE           reboot the unit
#   ./device.sh confirm DEVICE          (OpenWrt) keep this boot: cancel the automatic return to the stock firmware
#   ./device.sh to-stock DEVICE         (OpenWrt) make the stock firmware slot preferred and reboot into it
#   ./device.sh switch DEVICE STAMP     (stock firmware) boot again into out/STAMP, already in the other slot
#   ./device.sh nv-backup DEVICE        (OpenWrt with modem support) save the NV partitions to out/air6-nv-<time>.tar.gz
# DEVICE is what ssh accepts, for example root@192.168.1.1. Nothing reboots unless the command says so.
set -euo pipefail
cd "$(dirname "$0")"
SSH=${AIR6_SSH:-ssh}
run() { $SSH "$DEV" "$@"; }
kind() { run '[ -f /lib/upgrade/bootctrl.sh ] && echo stock || { [ -x /usr/sbin/air6-abguard ] && echo openwrt; } || echo other'; }
need() {
	[ "$(kind)" = "$1" ] && return 0
	[ "$1" = stock ] && echo "$DEV is not running the stock firmware" >&2 || echo "$DEV is not running OpenWrt" >&2
	exit 1
}
sha() { grep " $1\$" "out/$STAMP/SHA256SUMS" | cut -d' ' -f1; }
stamp() {
	STAMP=${1:?STAMP missing (a directory name under out/)}
	[ -f "out/$STAMP/CHECK.txt" ] || { echo "out/$STAMP/CHECK.txt not found" >&2; exit 1; }
	[ "$(tail -n 1 "out/$STAMP/CHECK.txt")" = "RESULT: PASS" ] || { echo "out/$STAMP did not pass the image check" >&2; exit 1; }
}

cmd=${1:-} DEV=${2:-}
[ -n "$cmd" ] && [ -n "$DEV" ] || { sed -n '2,10p' "$0"; exit 2; }
case "$cmd" in
status)
	case "$(kind)" in
	stock) run 'sh -s' < scripts/device/read_ab.sh ;;
	openwrt) run 'air6-abguard status' ;;
	*) echo "$DEV runs neither the stock firmware nor OpenWrt for the Air 6" >&2; exit 1 ;;
	esac ;;
install)
	stamp "${3:-}"; need stock
	if [ -f "out/$STAMP/MODEM_VERSION" ]; then
		# The image carries stock modem programs: they must match the modem firmware of the slot it goes into.
		want=$(sed -n 's/^rootfs=.*_\(V[0-9]*_[0-9]*_P[0-9]*\)$/\1/p' "out/$STAMP/MODEM_VERSION")
		got=$(run 'sh -s' < scripts/device/target_modem_version.sh || true)
		if [ "$want" != "$got" ]; then
			echo "the image's modem programs are $want but the modem firmware in the target slot is ${got:-unknown}" >&2
			[ "${AIR6_MODEM_MISMATCH:-0}" = 1 ] || { echo "refusing to install (AIR6_MODEM_MISMATCH=1 overrides)" >&2; exit 1; }
			echo "installing anyway (AIR6_MODEM_MISMATCH=1); the service also needs allow_version_mismatch" >&2
		fi
	fi
	echo "uploading boot.img"
	run 'cat > /tmp/air6-boot.img' < "out/$STAMP/boot.img"
	echo "uploading rootfs.img"
	run 'cat > /tmp/air6-rootfs.img' < "out/$STAMP/rootfs.img"
	run "BOOT_SHA=$(sha boot.img) ROOTFS_SHA=$(sha rootfs.img) sh -s" < scripts/device/install_openwrt.sh
	echo "installed; next: ./device.sh reboot $DEV" ;;
reboot)
	run 'sync; (sleep 1; reboot) >/dev/null 2>&1 &'
	echo "rebooting" ;;
confirm)
	need openwrt
	run 'air6-abguard status; air6-abguard confirm' ;;
to-stock)
	need openwrt
	run 'air6-abguard revert'
	run 'sync; (sleep 1; reboot) >/dev/null 2>&1 &'
	echo "rebooting into the stock firmware" ;;
switch)
	stamp "${3:-}"; need stock
	run "BOOT_SHA=$(sha boot.img) sh -s" < scripts/device/switch_to_openwrt.sh
	echo "next: ./device.sh reboot $DEV" ;;
nv-backup)
	# Same archive as LuCI's "Back up NV partitions" (made by the air6-modem package on the unit), checked here.
	need openwrt
	run '[ -x /usr/libexec/air6-modem/nv ]' || { echo "this image has no modem support (build it with AIR6_MODEM)" >&2; exit 1; }
	# The archive holds unit-specific data: private from the moment it is created.
	umask 077
	mkdir -p out
	OUT=out/air6-nv-$(date +%Y%m%d-%H%M%S).tar.gz
	run '/usr/libexec/air6-modem/nv create -' > "$OUT" || { rm -f "$OUT"; echo "backup failed" >&2; exit 1; }
	T=$(mktemp -d) && trap 'rm -rf "$T"' EXIT
	tar -C "$T" -xzf "$OUT" && (cd "$T" && sha256sum -c --quiet SHA256SUMS) || { echo "$OUT is damaged" >&2; exit 1; }
	echo "NV backup: $OUT ($(stat -c %s "$OUT") bytes; contains device-specific data, keep it private)" ;;
*)
	sed -n '2,10p' "$0"; exit 2 ;;
esac
