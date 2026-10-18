#!/bin/bash
# Check an Air 6 image dir before flashing: hashes, partition sizes, boot image identity and MTK signature, and the
# files the safety net and the board need in the rootfs. Writes <dir>/CHECK.txt; exit status 0 only on PASS.
# Runs inside the kit's builder container (needs unsquashfs, openssl, python3).
# Usage: scripts/check_image.sh IMAGE_DIR LG6851F_EXTERNALS_DIR
set -u
D=$1 X=$2
HERE=$(cd "$(dirname "$0")" && pwd)
KEYS=$X/lg6851f_sign_tool/fg370-2305-opensdk/mtk/tools/common/security/sign_master/hsm_test_keys/RSA2048
fail=0
ok() { echo "OK   $*"; }
ng() { echo "FAIL $*"; fail=1; }
has() { if echo "$LIST" | grep -q -E "$1"; then ok "rootfs: $2"; else ng "rootfs: $2"; fi; }
{
	echo "check_image $(date '+%F %T') $D"
	(cd "$D" && sha256sum -c --quiet SHA256SUMS) && ok "SHA256SUMS" || ng "SHA256SUMS"
	[ "$(stat -c %s "$D/boot.img")" = 33554432 ] && ok "boot.img size 32 MiB (boot_a/boot_b)" || ng "boot.img size"
	[ "$(stat -c %s "$D/rootfs.img")" = 134217728 ] && ok "rootfs.img size 128 MiB (rootfs_a/rootfs_b)" || ng "rootfs.img size"
	grep -q -a 'SoftBank Air 6 (A775)' "$D/boot.img" && ok "boot.img DTB model" || ng "boot.img DTB model"
	grep -q -a 'air6_dt_bootargs=1' "$D/boot.img" && ok "boot.img /chosen bootargs marker" || ng "boot.img bootargs marker"
	T=$(mktemp -d)
	openssl rsa -in "$KEYS/ROOT_prvk.pem" -pubout -out "$T/root.pub" 2>/dev/null &&
	openssl rsa -in "$KEYS/IMAGE_prvk.pem" -pubout -out "$T/img.pub" 2>/dev/null &&
	python3 -I "$HERE/resign_boot.py" --verify "$D/boot.img" "$T/root.pub" "$T/img.pub" > "$T/verify.log" 2>&1 &&
		ok "boot.img MTK signature (cert1 ROOT, cert2 IMAGE)" || { ng "boot.img MTK signature"; sed 's/^/     /' "$T/verify.log"; }
	rm -rf "$T"
	if LIST=$(unsquashfs -lls "$D/rootfs.img" 2>/dev/null); then
		has "^-rwx.* squashfs-root/usr/sbin/air6-abguard$" "/usr/sbin/air6-abguard (executable)"
		has "^-rwx.* squashfs-root/etc/init.d/air6-abguard$" "/etc/init.d/air6-abguard (executable)"
		has "^l.* squashfs-root/etc/rc.d/S11air6-abguard -> ../init.d/air6-abguard$" "/etc/rc.d/S11air6-abguard enabled"
		for n in wm wa dsp rom_patch; do
			has " squashfs-root/lib/firmware/mediatek/mt7996/mt7996_${n}_mt6990.bin$" "MT6990 Wi-Fi firmware ($n)"
		done
		# The MT6990 endpoint must calibrate from the board EEPROM only; a default EEPROM file must not be shipped.
		if echo "$LIST" | grep -q -E " squashfs-root/lib/firmware/mediatek/mt7996/mt7996_eeprom"; then
			ng "rootfs: a default mt7996 EEPROM file is present"
		else
			ok "rootfs: no default mt7996 EEPROM file"
		fi
		has " squashfs-root/etc/board.d/02_network$" "/etc/board.d/02_network"
		unsquashfs -cat "$D/rootfs.img" etc/board.d/02_network 2>/dev/null | grep -q "softbank,air6)" &&
			ok "rootfs: 02_network has the softbank,air6 case" || ng "rootfs: 02_network lacks the softbank,air6 case"
		unsquashfs -cat "$D/rootfs.img" etc/init.d/air6-abguard 2>/dev/null | grep -q "^START=11$" &&
			ok "rootfs: air6-abguard init START=11" || ng "rootfs: air6-abguard init START"
	else
		ng "rootfs.img is not a readable squashfs"
	fi
	[ "$fail" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
} 2>&1 | tee "$D/CHECK.txt"
grep -q '^RESULT: PASS$' "$D/CHECK.txt"
