#!/bin/bash
# Pack the Android boot v2 image, sign it with the MediaTek (MTK) sign_flow from the LG6851F tree (MT6990 SDK test keys, Python 3.10), pad both
# images to their partition sizes, write SHA256SUMS and PROVENANCE, keep the build's packages, run the image check.
# Usage (in the builder container): build/finish.sh OPENWRT_TREE LG6851F_EXTERNALS_DIR OUT_DIR FORK_COMMIT
set -euo pipefail
T=$1 X=$2 OUT=$3 FORK_COMMIT=$4
K=$(cd "$(dirname "$0")/.." && pwd)
BIN=$T/bin/targets/mediatek/mt6990
one() { set -- $(ls "$BIN"/$1 2>/dev/null); [ $# = 1 ] || { echo "expected one $1, found $#" >&2; exit 1; }; echo "$1"; }
# One assignment per line: with several on one line, set -e only sees the last command substitution.
KERNEL=$(one '*softbank_air6-squashfs-kernel.bin')
DTB=$(one '*softbank_air6-squashfs-dtb')
ROOTFS=$(one '*softbank_air6-squashfs-rootfs.img')
SDK=$X/lg6851f_sign_tool/fg370-2305-opensdk
TOOL=$SDK/mtk/tools/common/security/tool
KEYS=$SDK/mtk/tools/common/security/sign_master/hsm_test_keys/RSA2048
rm -rf "$OUT" && mkdir -p "$OUT/packages"
WORK=$(mktemp -d) && mkdir -p "$WORK/in"

python3 "$X/scripts/lg6851f_mkbootimg_v2.py" --meta "$X/target/linux/mediatek/image/lg6851f-boot-v2.json" \
	--kernel "$KERNEL" --dtb "$DTB" --out "$WORK/in/boot.img"
cp "$WORK/in/boot.img" "$WORK/in/boot.orig.img"
(cd "$TOOL" && PYTHONDONTWRITEBYTECODE=True PRODUCT_OUT="$WORK/in" BOARD_AVB_ENABLE= \
	python3.10 sign_flow.py image mt2737 default hsm=1 \
	root_key_path="$KEYS/ROOT" oem_key_path="$KEYS/IMAGE" root_key_padding=pss) > "$OUT/sign.log" 2>&1
cp "$WORK/in/boot-verified.img" "$OUT/boot.img" && truncate -s 33554432 "$OUT/boot.img"
cp "$ROOTFS" "$OUT/rootfs.img" && truncate -s 134217728 "$OUT/rootfs.img"
rm -rf "$WORK"
(cd "$OUT" && sha256sum boot.img rootfs.img > SHA256SUMS)

cp -a "$BIN/packages" "$OUT/packages/target"
cp -a "$T/bin/packages/." "$OUT/packages/feeds/"

kit_rev=$(git -c safe.directory="$K" -C "$K" rev-parse HEAD 2>/dev/null || echo none)
kit_dirty=$(git -c safe.directory="$K" -C "$K" status --porcelain 2>/dev/null | wc -l)
{
	echo "built: $(date -u '+%F %T') UTC"
	echo "openwrt fork: $FORK_COMMIT"
	echo "kit: $kit_rev (uncommitted changes: $kit_dirty)"
	. "$K/externals.lock"; echo "externals: $LG6851F_REPO @ $LG6851F_COMMIT"
	. "$K/stock-firmware.lock"
	echo "$STOCK_WIFI_FW" | awk 'NF == 3' | while read -r p n h; do
		got=$(sha256sum < "$T/files/lib/firmware/mediatek/mt7996/$n" | cut -d' ' -f1)
		[ "$got" = "$h" ] && known=listed || known="NOT in stock-firmware.lock"
		echo "wifi firmware: $n from stock $p, sha256 $got ($known)"
	done
	echo "kernel: $(sed -n 's/^LINUX_VERSION-6.18 = /6.18/p' "$T/target/linux/generic/kernel-6.18")"
	echo "mt76: $(sed -n 's/^PKG_SOURCE_VERSION:=//p' "$T/package/kernel/mt76/Makefile")"
	for f in "$T"/feeds/*/; do
		[ -d "$f/.git" ] && echo "feed $(basename "$f"): $(git -C "$f" rev-parse HEAD)"
	done
	echo "unsigned inputs: $(basename "$KERNEL") $(basename "$DTB") $(basename "$ROOTFS")"
	echo "kmod-mt6990-modem: $(grep -q '^CONFIG_PACKAGE_kmod-mt6990-modem=y' "$T/.config" && echo selected || echo not selected)"
	if [ -n "${AIR6_MODEM:-}" ]; then
		# The stock modem userspace in this image (not redistributable): version and every file (links by target).
		echo "modem: AIR6_MODEM=$AIR6_MODEM, $(paste -s -d ' ' "$K/local/modem/$AIR6_MODEM/MODEM_VERSION")"
		(cd "$T/files/usr/lib/air6-modem/stock" && find . \( -type f -o -type l \) | LC_ALL=C sort |
			while read -r f; do
				if [ -L "$f" ]; then echo "link $f -> $(readlink "$f")"; else echo "$(sha256sum < "$f" | cut -d' ' -f1) $f"; fi
			done) > "$OUT/MODEM_FILES"
		. "$K/modem-files.lock"
		v=$(sed -n 's/^rootfs=.*_\(V[0-9]*_[0-9]*_P[0-9]*\)$/\1/p' "$K/local/modem/$AIR6_MODEM/MODEM_VERSION")
		unknown=$(awk '$1 != "link" { print $2, $1 }' "$OUT/MODEM_FILES" | sed 's|^\./||' | while read -r p h; do
			echo "$STOCK_MODEM_HASHES" | awk -v v="$v" -v p="$p" -v h="$h" '$1 == v && $2 == p && $3 == h { f = 1 } END { exit !f }' ||
				echo "$p"
		done | wc -l)
		echo "modem files: $(grep -c . "$OUT/MODEM_FILES") (MODEM_FILES), $unknown not in modem-files.lock for $v"
		cp "$K/local/modem/$AIR6_MODEM/MODEM_VERSION" "$OUT/MODEM_VERSION"
	else
		echo "modem: none"
	fi
} > "$OUT/PROVENANCE"
"$K/scripts/check_image.sh" "$OUT" "$X"
