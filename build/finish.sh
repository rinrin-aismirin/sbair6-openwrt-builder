#!/bin/bash
# Pack the Android boot v2 image, sign it with the MediaTek (MTK) sign_flow from the LG6851F tree (MT6990 SDK test keys, Python 3.10), pad both
# images to their partition sizes, write SHA256SUMS, PACKAGES.sha256 and PROVENANCE, keep the build's packages, run the
# image check.
# Usage (in the builder container): build/finish.sh OPENWRT_TREE LG6851F_EXTERNALS_DIR OUT_DIR FORK_COMMIT
# OUT_DIR exists (created by build-in-container.sh for this build). Env: R (record fragments), P (private records), and
# the variables build-in-container.sh got from build.sh (RUN_ID, RUN_TOKEN, FORK_LOCK_COMMIT, O_*, KIT_START, ...).
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
mkdir "$OUT/packages"
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

(cd "$OUT" && find packages -type f | LC_ALL=C sort | xargs -r sha256sum) > "$OUT/PACKAGES.sha256"

kit_rev=$(git -c safe.directory="$K" -C "$K" rev-parse HEAD 2>/dev/null || echo none)
kit_end=$(GIT_OPTIONAL_LOCKS=0 "$K/build/kit-inputs.sh" "$K")
kit_docs=$(GIT_OPTIONAL_LOCKS=0 "$K/build/kit-inputs.sh" "$K" --docs)
# Build class (deviations from the reference: fork.lock, kit commit, no options, no modem).
dev=()
[ "$FORK_COMMIT" = "$FORK_LOCK_COMMIT" ] || dev+=("fork $FORK_COMMIT")
[ -z "$KIT_START" ] || dev+=("kit inputs")
[ "$kit_end" = "$KIT_START" ] && [ "$kit_rev" = "$KIT_HEAD_START" ] || dev+=("kit inputs changed during the build")
[ -z "$O_CONFIG" ] || dev+=(local-config)
[ -z "$O_PATCHES" ] || dev+=(kernel-patches)
[ -z "$O_ALLK" ] || dev+=(all-kmods)
[ -z "${AIR6_MODEM:-}" ] || dev+=("modem $AIR6_MODEM")
read -r nfiles flist < "$R/local-files" || nfiles=0
nfiles=${nfiles:-0}
[ "$nfiles" -gt 0 ] && overlay=1 || overlay=
if [ ${#dev[@]} = 0 ]; then
	class=reference
	[ -z "$overlay" ] || class="reference + rootfs overlay"
else
	[ -z "$overlay" ] || dev+=("rootfs overlay")
	class="modified: $(printf '%s, ' "${dev[@]}" | sed 's/, $//')"
fi
kpkg=$(ls "$OUT/packages/target" 2>/dev/null | sed -n 's/\.apk$//; /^kernel-[0-9]/p' | head -n 1)
fw_origin() { if [ -f "$R/firmware-replaced" ] && grep -q -x -F "$1" "$R/firmware-replaced"; then echo "replaced by local/files"; else echo local/firmware; fi; }
{
	echo "build: $RUN_ID"
	echo "run token: $RUN_TOKEN"
	echo "started: $START_TIME UTC"
	echo "built: $(date -u '+%F %T') UTC"
	echo "options: $(cat "$R/options" | grep . || echo none)"
	echo "class: $class"
	echo "openwrt fork: $FORK_COMMIT (fork.lock: $FORK_LOCK_COMMIT)"
	echo "kit: $kit_rev"
	[ "$kit_rev" = "$KIT_HEAD_START" ] || echo "kit commit at start: $KIT_HEAD_START (changed during the build)"
	[ -z "$KIT_START" ] || echo "$KIT_START" | sed 's/^/kit input changed at start: /'
	[ "$kit_end" = "$KIT_START" ] || echo "$kit_end" | sed 's/^/kit input at the end of the build: /'
	[ -z "$kit_docs" ] || echo "kit docs changed: $(echo "$kit_docs" | wc -l) file(s) (no effect on the build)"
	. "$K/externals.lock"; echo "externals: $LG6851F_REPO @ $LG6851F_COMMIT"
	if [ -n "$overlay" ]; then
		echo "local/files: $nfiles file(s), list sha256 $flist (list in private/)"
		sed 's/^/local\/files notice: /' "$R/local-files-notices"
		if [ -f "$R/local-files-modules" ]; then
			echo "local/files replaces kernel modules: the packages of this build are not claimed to match the modules in the image"
		fi
		if [ -f "$R/local-files-modconf" ]; then
			echo "local/files: module load settings changed"
		fi
	else
		echo "local/files: not used"
	fi
	if [ -f "$R/kernel-patches" ]; then
		echo "kernel patches into target/linux/generic/$(cat "$R/kernel-patches-dir"):"
		sed 's/^/  /' "$R/kernel-patches"
	fi
	if [ -f "$R/all-kmods-verified" ]; then
		grep -v -E '^[[:space:]]*(#.*)?$' "$R/all-kmods.exclude" | sed 's/^/all-kmods left out: /'
		echo "all-kmods: $(cat "$R/all-kmods-verified")"
	fi
	[ ! -f "$R/local-packages" ] || sed 's/^/local\/diffconfig package: /' "$R/local-packages"
	echo "openwrt .config sha256: $(sha256sum < "$P/openwrt.config" | cut -d' ' -f1) (in private/)"
	echo "kernel .config sha256: $(sha256sum < "$P/kernel.config" | cut -d' ' -f1) (in private/)"
	echo "kernel package: ${kpkg:-not found} (kmod packages of this build depend on it)"
	. "$K/stock-firmware.lock"
	echo "$STOCK_WIFI_FW" | awk 'NF == 3' | while read -r p n h; do
		got=$(sha256sum < "$T/files/lib/firmware/mediatek/mt7996/$n" | cut -d' ' -f1)
		[ "$got" = "$h" ] && known=listed || known="NOT in stock-firmware.lock"
		origin=$(fw_origin "$n")
		if [ "$origin" = local/firmware ] && [ "$known" = listed ]; then
			echo "wifi firmware (as placed in the build tree's files/): $n from stock $p, sha256 $got ($known)"
		else
			echo "wifi firmware (as placed in the build tree's files/): $n from $origin, sha256 $got ($known)"
		fi
	done
	echo "kernel: $(sed -n 's/^LINUX_VERSION-6.18 = /6.18/p' "$T/target/linux/generic/kernel-6.18")"
	echo "mt76: $(sed -n 's/^PKG_SOURCE_VERSION:=//p' "$T/package/kernel/mt76/Makefile")"
	for f in "$T"/feeds/*/; do
		[ -d "$f/.git" ] && echo "feed $(basename "$f"): $(git -C "$f" rev-parse HEAD)"
	done
	echo "unsigned inputs: $(basename "$KERNEL") $(basename "$DTB") $(basename "$ROOTFS")"
	echo "packages: $(grep -c . "$OUT/PACKAGES.sha256") files (PACKAGES.sha256), for a unit running this build's image"
	echo "kmod-mt6990-modem: $(grep -q '^CONFIG_PACKAGE_kmod-mt6990-modem=y' "$T/.config" && echo selected || echo not selected)"
	if [ -n "${AIR6_MODEM:-}" ]; then
		# The stock modem userspace in this image (not redistributable): version and every file (links by target).
		echo "modem: AIR6_MODEM=$AIR6_MODEM, $(paste -s -d ' ' "$R/modem-version")"
		(cd "$T/files/usr/lib/air6-modem/stock" && find . \( -type f -o -type l \) | LC_ALL=C sort |
			while read -r f; do
				if [ -L "$f" ]; then echo "link $f -> $(readlink "$f")"; else echo "$(sha256sum < "$f" | cut -d' ' -f1) $f"; fi
			done) > "$OUT/MODEM_FILES"
		. "$K/modem-files.lock"
		v=$(sed -n 's/^rootfs=.*_\(V[0-9]*_[0-9]*_P[0-9]*\)$/\1/p' "$R/modem-version")
		unknown=$(awk '$1 != "link" { print $2, $1 }' "$OUT/MODEM_FILES" | sed 's|^\./||' | while read -r p h; do
			echo "$STOCK_MODEM_HASHES" | awk -v v="$v" -v p="$p" -v h="$h" '$1 == v && $2 == p && $3 == h { f = 1 } END { exit !f }' ||
				echo "$p"
		done | wc -l)
		echo "modem files: $(grep -c . "$OUT/MODEM_FILES") (MODEM_FILES), $unknown not in modem-files.lock for $v"
		cp "$R/modem-version" "$OUT/MODEM_VERSION"
	else
		echo "modem: none"
	fi
	echo "This record says what went into the build. It does not say that the image works, that it equals another"
	echo "build, or that any file here may be passed on (local/files and stock files can be inside the images)."
} > "$OUT/PROVENANCE"
"$K/scripts/check_image.sh" "$OUT" "$X"
