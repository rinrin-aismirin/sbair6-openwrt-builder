#!/bin/bash
# Runs inside the kit's builder container as user "build".
# Mounts: /kit (this repo, ro), /fork (the OpenWrt fork, ro), /home/build/work (cache volume). The build tree
# borrows the fork's git objects, so later debug runs in that tree need /fork mounted as well.
# Env: FORK_COMMIT (commit of the fork to build), STAMP (output name).
# Result: $W/kit-out/$STAMP (boot.img, rootfs.img, SHA256SUMS, PROVENANCE, CHECK.txt, packages/); log in
# $W/kit-status/$STAMP/progress.log.
set -euo pipefail
W=/home/build/work K=/kit
S=$W/kit-status/$STAMP T=$W/kit-tree X=$W/kit-cache/lg
mkdir -p "$S" "$W/dl" "$W/kit-cache"
st() { echo "$(date '+%F %T') $*" | tee -a "$S/progress.log"; }
trap 'st "FAILED (line $LINENO)"' ERR

st "tree: fork $FORK_COMMIT"
# The mounts are owned by another uid; this container's git config is ephemeral. git 2.34 ignores -c for this.
git config --global --add safe.directory '*'
# A real git checkout, not an archive: OpenWrt derives the revision and the base-files package version from git
# (an archive gives "unknown", which apk rejects). --shared borrows the objects of the read-only /fork mount.
rm -rf "$T"
git clone -q --shared --no-checkout /fork "$T"
git -C "$T" -c advice.detachedHead=false checkout -q "$FORK_COMMIT"
ln -s ../dl "$T/dl"

st "externals"
"$K/build/fetch-externals.sh" "$K/externals.lock" "$X" > "$S/externals.log" 2>&1

st "inject: Wi-Fi firmware, local overlay"
# Wi-Fi firmware from the user's own unit (./build.sh pull-fw); the names are those the fork's mt76 patch loads.
. "$K/stock-firmware.lock"
mkdir -p "$T/files/lib/firmware/mediatek/mt7996"
for n in $(echo "$STOCK_WIFI_FW" | awk 'NF == 3 { print $2 }'); do
	cp "$K/local/firmware/mt7996/$n" "$T/files/lib/firmware/mediatek/mt7996/"
done
if [ -d "$K/local/files" ]; then
	cp -a "$K/local/files/." "$T/files/"
	# local files must be world-readable on the host to reach the build user; tighten what dropbear checks
	[ -d "$T/files/etc/dropbear" ] && chmod 700 "$T/files/etc/dropbear" && chmod 600 "$T/files/etc/dropbear/"*
fi
# Optional modem support (AIR6_MODEM=<version>, resolved by build.sh): the owner's pulled stock modem userspace.
if [ -n "${AIR6_MODEM:-}" ]; then
	M="$K/local/modem/$AIR6_MODEM"
	[ -f "$M/MODEM_VERSION" ] || { st "modem files missing: local/modem/$AIR6_MODEM"; exit 1; }
	mkdir -p "$T/files/usr/lib/air6-modem"
	cp -a "$M/root" "$T/files/usr/lib/air6-modem/stock"
	cp "$M/MODEM_VERSION" "$T/files/usr/lib/air6-modem/MODEM_VERSION"
	(cd "$T/files/usr/lib/air6-modem/stock" && sha256sum -c --quiet "$M/SHA256SUMS") > "$S/modem-files.log" 2>&1 ||
		{ st "modem files in local/modem/$AIR6_MODEM changed since pull-modem (see modem-files.log)"; exit 1; }
fi

cd "$T"
st "feeds"
if [ -f "$K/config/feeds.conf" ]; then cp "$K/config/feeds.conf" feeds.conf; fi
# The modem packages run the owner's stock files, so they live in this kit (feed/), not in the fork. Linked in place:
# the LuCI package versions come from this repository's git history.
if [ -n "${AIR6_MODEM:-}" ]; then
	[ -f feeds.conf ] || cp feeds.conf.default feeds.conf
	echo "src-link air6 $K/feed" >> feeds.conf
fi
./scripts/feeds update -a > "$S/feeds.log" 2>&1
./scripts/feeds install -a >> "$S/feeds.log" 2>&1

st "config"
cp "$K/config/air6.diffconfig" .config
# Owner additions (git-ignored): extra package selections such as the modem packages.
[ -f "$K/local/diffconfig" ] && cat "$K/local/diffconfig" >> .config
# The feed "air6" exists only in this build: keep it out of the unit's apk repository list.
[ -z "${AIR6_MODEM:-}" ] || printf 'CONFIG_PACKAGE_kmod-mt6990-modem=y\nCONFIG_PACKAGE_air6-modem=y\nCONFIG_PACKAGE_luci-app-air6-modem=y\n# CONFIG_FEED_air6 is not set\n' >> .config
make defconfig > "$S/defconfig.log" 2>&1
grep -q '^CONFIG_TARGET_mediatek_mt6990_DEVICE_softbank_air6=y$' .config || { st "device not selected"; exit 1; }
[ -z "${AIR6_MODEM:-}" ] || grep -q '^CONFIG_PACKAGE_kmod-mt6990-modem=y$' .config || { st "modem kmod not selectable"; exit 1; }
[ -z "${AIR6_MODEM:-}" ] || grep -q '^CONFIG_PACKAGE_luci-app-air6-modem=y$' .config || { st "modem packages not selectable (feed air6)"; exit 1; }
[ -z "${AIR6_MODEM:-}" ] || grep -q '^# CONFIG_FEED_air6 is not set$' .config || { st "feed air6 would be listed on the unit"; exit 1; }

st "download"
make download -j8 > "$S/download.log" 2>&1
st "build"
make -j"$(nproc)" > "$S/build.log" 2>&1
KCONF=$(ls -d build_dir/target-*/linux-mediatek_mt6990/linux-*/.config)
# The fork's 972i-net-ethernet-mediatek-mt6990-sdk-irq-layout.patch makes mtk_poll_controller() pass the
# net_device to mtk_handle_irq_rx(), which expects the struct mtk_eth. That code is only built with
# NET_POLL_CONTROLLER, so refuse a kernel config that enables it.
if grep -q '^CONFIG_NET_POLL_CONTROLLER=y' "$KCONF"; then st "NET_POLL_CONTROLLER is enabled (see build-in-container.sh)"; exit 1; fi

st "finish: pack, sign, check"
"$K/build/finish.sh" "$T" "$X" "$W/kit-out/$STAMP" "$FORK_COMMIT" > "$S/finish.log" 2>&1
st "DONE"
