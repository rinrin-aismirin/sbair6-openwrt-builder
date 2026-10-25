#!/bin/bash
# Runs inside the kit's builder container as user "build", started by `./build.sh start`.
# Mounts: /kit (this repo, ro), /fork (the OpenWrt fork, ro), /home/build/work (cache volume). The build tree
# borrows the fork's git objects, so later debug runs in that tree need /fork mounted as well.
# Env: FORK_COMMIT (commit to build), FORK_LOCK_COMMIT (fork.lock's commit), RUN_ID, RUN_TOKEN, AIR6_MODEM,
#   O_FILES / O_CONFIG / O_PATCHES / O_ALLK (selected options, "1" or empty), KIT_START (kit build inputs that
#   differed from the kit commit at start), START_TIME.
# Result: $W/kit-out/$RUN_ID (boot.img, rootfs.img, SHA256SUMS, PACKAGES.sha256, PROVENANCE, CHECK.txt, packages/,
# private/); log in $W/kit-status/$RUN_ID/progress.log.
# Inputs are read from /kit while the build runs (no snapshot). Every record of an input is made from the copy this
# script read, at the step that read it, never from re-reading /kit later.
set -euo pipefail
W=/home/build/work K=/kit
S=$W/kit-status/$RUN_ID OUT=$W/kit-out/$RUN_ID T=$W/kit-tree X=$W/kit-cache/lg
mkdir -p "$W/kit-status" "$W/kit-out" "$W/dl" "$W/kit-cache"
# This build's directories are created here and never reused: an existing one belongs to another build.
mkdir "$S" || { echo "kit-status/$RUN_ID exists; another build owns it" >&2; exit 1; }
echo "$RUN_TOKEN" > "$S/RUN_TOKEN"
st() { echo "$(date '+%F %T') $*" | tee -a "$S/progress.log"; }
# Every way out except DONE ends the log with FAILED (status reads it).
trap 'FAIL_LINE=$LINENO' ERR
trap 'rc=$?; rm -rf "$W/kit-tmp/$RUN_ID"; [ $rc = 0 ] || st "FAILED (exit $rc${FAIL_LINE:+, line $FAIL_LINE})"' EXIT
mkdir "$OUT" || { st "kit-out/$RUN_ID exists; another build owns it"; exit 1; }
echo "$RUN_TOKEN" > "$OUT/RUN_TOKEN"
# private/: the owner's inputs as consumed and the resolved configurations (mode 0600 in a 0700 directory).
P=$OUT/private
mkdir -m 0700 "$P"
priv() { install -m 0600 "$1" "$P/$2"; }
# Public record fragments for finish.sh.
R=$S/record
mkdir "$R"
printf '%s' "$KIT_START" > "$R/kit-start"
opts=""
[ -z "$O_FILES" ] && opts="$opts --no-local-files"
[ -n "$O_CONFIG" ] && opts="$opts --local-config"
[ -n "$O_PATCHES" ] && opts="$opts --kernel-patches"
[ -n "$O_ALLK" ] && opts="$opts --all-kmods"
[ -n "${AIR6_MODEM:-}" ] && opts="$opts AIR6_MODEM=$AIR6_MODEM"
echo "${opts# }" > "$R/options"

st "tree: fork $FORK_COMMIT"
# The mounts are owned by another uid; this container's git config is ephemeral. git 2.34 ignores -c for this.
git config --global --add safe.directory '*'
# A real git checkout, not an archive: OpenWrt derives the revision and the base-files package version from git
# (an archive gives "unknown", which apk rejects). --shared borrows the objects of the read-only /fork mount.
rm -rf "$T"
git clone -q --shared --no-checkout /fork "$T"
git -C "$T" -c advice.detachedHead=false checkout -q "$FORK_COMMIT"
ln -s ../dl "$T/dl"

if [ -n "$O_PATCHES" ]; then
	st "kernel patches"
	# The pending directory of the kernel line this tree builds (not a fixed version).
	V=$(sed -n 's/^KERNEL_PATCHVER:=//p' "$T/target/linux/mediatek/Makefile")
	PD=$T/target/linux/generic/pending-$V
	[ -n "$V" ] && [ -d "$PD" ] || { st "kernel patches: the fork has no target/linux/generic/pending-$V"; exit 1; }
	mkdir -m 0700 "$P/kernel-patches"
	for f in "$K"/local/kernel-patches/*.patch; do priv "$f" "kernel-patches/$(basename "$f")"; done
	echo "pending-$V" > "$R/kernel-patches-dir"
	for f in "$P"/kernel-patches/*.patch; do
		n=$(basename "$f")
		[ ! -e "$PD/$n" ] || { st "kernel patch $n: the fork already has a patch with this name"; exit 1; }
		cp "$f" "$PD/$n"
		echo "$n $(sha256sum < "$f" | cut -d' ' -f1)" >> "$R/kernel-patches"
	done
fi

st "externals"
"$K/build/fetch-externals.sh" "$K/externals.lock" "$X" > "$S/externals.log" 2>&1

st "inject: Wi-Fi firmware, local overlay"
# Wi-Fi firmware from the user's own unit (./build.sh pull-fw); the names are those the fork's mt76 patch loads.
. "$K/stock-firmware.lock"
FWP=lib/firmware/mediatek/mt7996
mkdir -p "$T/files/$FWP"
for n in $(echo "$STOCK_WIFI_FW" | awk 'NF == 3 { print $2 }'); do
	cp "$K/local/firmware/mt7996/$n" "$T/files/$FWP/"
done
: > "$R/local-files"
if [ -n "$O_FILES" ] && [ -d "$K/local/files" ]; then
	# Copy, list and summarise in a directory only this build user can read; the list itself goes to private/ only.
	L=$W/kit-tmp/$RUN_ID
	mkdir -p "$W/kit-tmp" && rm -rf "$L" && mkdir -m 0700 "$L" "$L/files"
	cp -a "$K/local/files/." "$L/files/"
	# The list below is tab-separated, one entry per line: paths and link targets must not contain either.
	if (cd "$L/files" && find . \( -name $'*\n*' -o -name $'*\t*' -o -lname $'*\n*' -o -lname $'*\t*' \) | grep -q .); then
		st "local/files: a path or a link target contains a newline or a tab"; exit 1
	fi
	# Tab-separated: kind, mode, sha256 (file) or target (link), path. Made from this copy, which goes into the image.
	(umask 077; cd "$L/files" && find . -mindepth 1 \( -type f -o -type l \) | sed 's|^\./||' | LC_ALL=C sort |
		while IFS= read -r f; do
			if [ -L "$f" ]; then
				printf 'link\t-\t%s\t%s\n' "$(readlink "$f")" "$f"
			else
				printf 'file\t%s\t%s\t%s\n' "$(stat -c %a "$f")" "$(sha256sum < "$f" | cut -d' ' -f1)" "$f"
			fi
		done > "$P/local-files.list")
	awk -F '\t' '{ print $4 }' "$P/local-files.list" > "$L/paths"
	# Public summary for finish.sh: count and list digest, notice paths, flags. No contents or link targets.
	echo "$(grep -c . "$L/paths" || true) $(sha256sum < "$P/local-files.list" | cut -d' ' -f1)" > "$R/local-files"
	grep -E '^(lib/modules/|lib/firmware/|etc/modules\.conf$|etc/modules\.d/|etc/init\.d/|etc/rc\.d/|etc/uci-defaults/|lib/apk/|etc/apk/)' \
		"$L/paths" > "$R/local-files-notices" || true
	grep -q '^lib/modules/' "$L/paths" && touch "$R/local-files-modules"
	grep -q -E '^etc/modules\.(conf$|d/)' "$L/paths" && touch "$R/local-files-modconf"
	for n in $(echo "$STOCK_WIFI_FW" | awk 'NF == 3 { print $2 }'); do
		grep -q -x -F "$FWP/$n" "$L/paths" && echo "$n" >> "$R/firmware-replaced"
	done
	cp -a "$L/files/." "$T/files/"
	rm -rf "$L"
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
	cp "$M/MODEM_VERSION" "$R/modem-version"
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
# Order: kit config, local/diffconfig (--local-config), all kernel modules (--all-kmods), modem selections.
priv "$K/config/air6.diffconfig" air6.diffconfig
cp "$P/air6.diffconfig" .config
LC=
if [ -n "$O_CONFIG" ]; then
	priv "$K/local/diffconfig" local.diffconfig
	LC=$P/local.diffconfig
	cat "$LC" >> .config
fi
EXCL=
if [ -n "$O_ALLK" ]; then
	priv "$K/config/all-kmods.exclude" all-kmods.exclude
	EXCL=$(grep -v -E '^[[:space:]]*(#.*)?$' "$P/all-kmods.exclude" | awk '{ print $1 }')
	cp "$P/all-kmods.exclude" "$R/all-kmods.exclude"
	echo 'CONFIG_ALL_KMODS=y' >> .config
	for e in $EXCL; do
		if [ -n "$LC" ] && awk -F= -v k="CONFIG_PACKAGE_$e" '$1 == k && ($2 == "y" || $2 == "m") { f = 1 } END { exit !f }' "$LC"; then
			st "local/diffconfig selects $e, which --all-kmods leaves out (config/all-kmods.exclude)"; exit 1
		fi
		echo "# CONFIG_PACKAGE_$e is not set" >> .config
	done
fi
# The feed "air6" exists only in this build: keep it out of the unit's apk repository list.
[ -z "${AIR6_MODEM:-}" ] || printf 'CONFIG_PACKAGE_kmod-mt6990-modem=y\nCONFIG_PACKAGE_air6-modem=y\nCONFIG_PACKAGE_luci-app-air6-modem=y\n# CONFIG_FEED_air6 is not set\n' >> .config
make defconfig > "$S/defconfig.log" 2>&1
grep -q '^CONFIG_TARGET_mediatek_mt6990_DEVICE_softbank_air6=y$' .config || { st "device not selected"; exit 1; }
[ -z "${AIR6_MODEM:-}" ] || grep -q '^CONFIG_PACKAGE_kmod-mt6990-modem=y$' .config || { st "modem kmod not selectable"; exit 1; }
[ -z "${AIR6_MODEM:-}" ] || grep -q '^CONFIG_PACKAGE_luci-app-air6-modem=y$' .config || { st "modem packages not selectable (feed air6)"; exit 1; }
[ -z "${AIR6_MODEM:-}" ] || grep -q '^# CONFIG_FEED_air6 is not set$' .config || { st "feed air6 would be listed on the unit"; exit 1; }
# The resolved configuration must be what the options asked for (checked before the long build).
# Stricter than "only without --all-kmods": these select userspace packages too, which the kit does not support.
for s in ALL BUILDBOT ALL_NONSHARED; do
	grep -q "^CONFIG_$s=y$" .config && { st "CONFIG_$s=y is set (not supported; --all-kmods selects kernel modules only)"; exit 1; }
done
if [ -n "$O_ALLK" ]; then
	grep -q '^CONFIG_ALL_KMODS=y$' .config || { st "--all-kmods: CONFIG_ALL_KMODS is not set after defconfig"; exit 1; }
	absent=
	for e in $EXCL; do
		if awk -F= -v k="CONFIG_PACKAGE_$e" '$1 == k && ($2 == "y" || $2 == "m") { f = 1 } END { exit !f }' .config; then
			st "--all-kmods: $e is selected after defconfig (a dependency?)"; exit 1
		fi
		# No line at all: not selected either (for example its feed is not used, or Kconfig did not write the symbol).
		grep -q -x -F "# CONFIG_PACKAGE_$e is not set" .config || absent="$absent $e"
	done
	echo "verified: CONFIG_ALL_KMODS=y; left out: $(echo $EXCL)${absent:+; not present in the resolved .config:$absent}" > "$R/all-kmods-verified"
else
	grep -q '^CONFIG_ALL_KMODS=y$' .config && { st "CONFIG_ALL_KMODS=y is set without --all-kmods"; exit 1; }
fi
if [ -n "$LC" ]; then
	bad=
	sed -n 's/^CONFIG_PACKAGE_\([^=]*\)=\([ym]\)$/\1 \2/p' "$LC" | while read -r pkg want; do
		got=$(awk -F= -v k="CONFIG_PACKAGE_$pkg" '$1 == k { print $2 }' .config)
		echo "$pkg requested=$want effective=${got:-not set}"
	done > "$R/local-packages"
	while read -r pkg req eff; do
		case "${req#*=}:${eff#*=}" in
		y:y|m:m|m:y) ;;
		*) bad="$bad $pkg(${req#*=}->${eff#*=})" ;;
		esac
	done < "$R/local-packages"
	[ -z "$bad" ] || { st "local/diffconfig: packages not selected as requested:$bad"; exit 1; }
fi
priv .config openwrt.config

st "download"
make download -j8 > "$S/download.log" 2>&1
st "build"
make -j"$(nproc)" > "$S/build.log" 2>&1
KCONF=$(ls -d build_dir/target-*/linux-mediatek_mt6990/linux-*/.config)
priv "$KCONF" kernel.config

st "finish: pack, sign, check"
R="$R" P="$P" "$K/build/finish.sh" "$T" "$X" "$OUT" "$FORK_COMMIT" > "$S/finish.log" 2>&1
st "DONE"
