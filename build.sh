#!/bin/bash
# Builds the OpenWrt image for the Air 6 in a Docker container. Run these commands on your Linux computer.
#   ./build.sh image                  build the Docker image that the build runs in (once)
#   ./build.sh fetch                  download the OpenWrt fork into openwrt/, at the commit in fork.lock
#   ./build.sh pull-fw [USER@]DEVICE  copy the Wi-Fi firmware from a unit running the stock firmware (once)
#   ./build.sh pull-modem [USER@]DEVICE [SLOT] | FILE
#                                     copy the modem userspace (optional modem support, see docs/modem.md) from
#                                     a unit running the stock firmware (default: the slot it does not run from)
#                                     or from a saved stock root filesystem image FILE
#   ./build.sh start                  start a build in the background and print its build ID (STAMP)
#   ./build.sh status STAMP           show the progress of a build; the last line says running, done or failed
#   ./build.sh collect STAMP          copy a finished build to out/STAMP/ and print the image check result
#   ./build.sh logs STAMP             copy the logs of a build to out/logs-STAMP/ (for a failed build)
# Advanced:
#   ./build.sh start DIR [COMMIT]     build another checkout DIR of the fork, at COMMIT (default: its HEAD)
#   DOCKER_CONTEXT=NAME               use this Docker context (default: the current one; tested with rootless Docker)
#   AIR6_VOLUME=NAME                  Docker volume for downloads and the build tree (default: air6-kit-work)
#   AIR6_SSH="ssh -i KEY ..."         ssh command for pull-fw (default: ssh)
#   AIR6_MODEM=1 | VERSION            start: include the optional modem support with the files from pull-modem
set -euo pipefail
cd "$(dirname "$0")"
D="docker${DOCKER_CONTEXT:+ --context $DOCKER_CONTEXT}"
IMG=air6-kit-builder:22.04 VOL=${AIR6_VOLUME:-air6-kit-work}
. ./fork.lock
. ./stock-firmware.lock
FW=local/firmware/mt7996
fw_missing() { echo "$STOCK_WIFI_FW" | awk 'NF == 3 { print $2 }' | while read -r n; do [ -f "$FW/$n" ] || echo "$n"; done; }
case "${1:-}" in
image)
	$D build -t "$IMG" docker/ ;;
fetch)
	case "$FORK_REPO" in *example.invalid*)
		echo "fork.lock: FORK_REPO is still a placeholder; clone the fork yourself and pass its path to 'start'" >&2
		exit 1 ;;
	esac
	if [ -d openwrt/.git ]; then
		git -C openwrt fetch -q origin "$FORK_BRANCH"
	else
		git clone -q --no-checkout --branch "$FORK_BRANCH" "$FORK_REPO" openwrt
	fi
	git -C openwrt -c advice.detachedHead=false checkout -q "$FORK_COMMIT"
	[ "$(git -C openwrt rev-parse HEAD)" = "$FORK_COMMIT" ] || { echo "fetch: wrong commit" >&2; exit 1; }
	echo "openwrt/ at $FORK_COMMIT" ;;
pull-fw)
	DEST=${2:?usage: ./build.sh pull-fw [USER@]DEVICE}
	TMP=$(mktemp -d) && trap 'rm -rf "$TMP"' EXIT
	${AIR6_SSH:-ssh} "$DEST" "sh -s $(echo "$STOCK_WIFI_FW" | awk 'NF == 3 { printf "%s ", $1 }')" \
		< scripts/device/stock_wifi_fw.sh > "$TMP/fw.tar"
	tar -C "$TMP" -xf "$TMP/fw.tar"
	mkdir -p "$FW"
	echo "$STOCK_WIFI_FW" | awk 'NF == 3' | while read -r p n h; do
		got=$(sha256sum < "$TMP$p" | cut -d' ' -f1)
		[ "$got" = "$h" ] || echo "warning: $p has sha256 $got, not the one in stock-firmware.lock" >&2
		cp "$TMP$p" "$FW/$n"
		echo "$FW/$n <- $p"
	done ;;
pull-modem)
	SRC=${2:?usage: ./build.sh pull-modem [USER@]DEVICE [SLOT] | FILE}
	. ./modem-files.lock
	FILES=$(echo "$STOCK_MODEM_FILES" | awk NF)
	TMP=$(mktemp -d) && trap 'rm -rf "$TMP"' EXIT
	if [ -f "$SRC" ]; then
		# A saved stock root filesystem (squashfs), for a slot that no longer holds the stock firmware.
		IMGF=$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")
		$D run --rm -i --user 0 -v "$IMGF:/img:ro" "$IMG" sh -c '
			set -e
			unsquashfs -q -n -no-xattrs -d /x /img lib/upgrade/bootctrl.sh "$@" >&2
			[ -f /x/lib/upgrade/bootctrl.sh ] || { echo "abort: not a stock root filesystem" >&2; exit 1; }
			tar -C /x -cf - "$@"' sh $FILES > "$TMP/m.tar"
		$D run --rm -i --user 0 -v "$IMGF:/img:ro" "$IMG" sh -c '
			printf "slot=file\nmd1img=\nrootfs=%s\n" \
				"$(unsquashfs -l /img etc/mddb | grep -o -m1 "MOLY[A-Z0-9_]*_V[0-9]*_[0-9]*_P[0-9]*")"' \
			> "$TMP/MODEM_VERSION"
	else
		SLOT=${3:-}
		if [ -z "$SLOT" ]; then
			RUN=$(${AIR6_SSH:-ssh} "$SRC" "sed -n 's/.*bootslot=\([ab]\).*/\1/p' /proc/cmdline")
			case "$RUN" in a) SLOT=b ;; b) SLOT=a ;; *) echo "cannot read the running slot" >&2; exit 1 ;; esac
		fi
		${AIR6_SSH:-ssh} "$SRC" "sh -s $SLOT $(echo $FILES)" < scripts/device/stock_modem_files.sh > "$TMP/m.tar"
	fi
	mkdir "$TMP/root"
	tar -C "$TMP/root" -xf "$TMP/m.tar"
	if [ -d "$TMP/root/tmp" ]; then
		mv "$TMP"/root/tmp/air6-pull-modem-ver.*/MODEM_VERSION "$TMP/MODEM_VERSION"
		rm -r "$TMP/root/tmp"
	fi
	VER=$(sed -n 's/^rootfs=.*_\(V[0-9]*_[0-9]*_P[0-9]*\)$/\1/p' "$TMP/MODEM_VERSION")
	[ -n "$VER" ] || { echo "no modem version found in the stock root filesystem" >&2; exit 1; }
	MDV=$(sed -n 's/^md1img=.*_\(V[0-9]*_[0-9]*_P[0-9]*\)$/\1/p' "$TMP/MODEM_VERSION")
	[ -z "$MDV" ] || [ "$MDV" = "$VER" ] ||
		echo "warning: the slot's modem firmware is $MDV but its root filesystem is $VER" >&2
	echo "$STOCK_MODEM_HASHES" | grep -q "^$VER " || echo "warning: modem version $VER is not in modem-files.lock" >&2
	echo "$FILES" | while read -r p; do
		[ -L "$TMP/root/$p" ] && continue
		[ -f "$TMP/root/$p" ] || { echo "missing: $p" >&2; exit 1; }
		h=$(echo "$STOCK_MODEM_HASHES" | awk -v v="$VER" -v p="$p" '$1 == v && $2 == p { print $3 }')
		got=$(sha256sum < "$TMP/root/$p" | cut -d' ' -f1)
		[ -z "$h" ] || [ "$h" = "$got" ] || echo "warning: $p has sha256 $got, not the one in modem-files.lock" >&2
	done
	OUT=local/modem/$VER
	rm -rf "$OUT" && mkdir -p "$OUT"
	cp -a "$TMP/root" "$OUT/root"
	# The build runs as another user in the container: make the copy readable (no secrets in these files).
	chmod -R a+rX "$OUT/root"
	cp "$TMP/MODEM_VERSION" "$OUT/MODEM_VERSION"
	(cd "$OUT/root" && find . -type f | sort | xargs sha256sum) > "$OUT/SHA256SUMS"
	echo "$OUT: $(grep -c . "$OUT/SHA256SUMS") files, version $VER"; cat "$OUT/MODEM_VERSION" ;;
start)
	[ -z "$(fw_missing)" ] || { echo "Wi-Fi firmware missing in $FW/: run './build.sh pull-fw [USER@]DEVICE' first" >&2; exit 1; }
	if [ $# -ge 2 ]; then
		FORK_DIR=$(cd "$2" && pwd) REF=${3:-HEAD}
	else
		FORK_DIR=$PWD/openwrt REF=$FORK_COMMIT
		[ -d "$FORK_DIR/.git" ] || { echo "openwrt/ not found; run './build.sh fetch' first" >&2; exit 1; }
	fi
	C=$(git -C "$FORK_DIR" rev-parse --verify "$REF^{commit}")
	MODEM=
	if [ -n "${AIR6_MODEM:-}" ]; then
		if [ "$AIR6_MODEM" = 1 ]; then
			n=$(ls local/modem 2>/dev/null | wc -l)
			[ "$n" = 1 ] || { echo "AIR6_MODEM=1 needs exactly one version in local/modem/ (found $n); set AIR6_MODEM=<version>" >&2; exit 1; }
			MODEM=$(ls local/modem)
		else
			MODEM=$AIR6_MODEM
		fi
		[ -f "local/modem/$MODEM/MODEM_VERSION" ] || { echo "local/modem/$MODEM not found: run './build.sh pull-modem' first" >&2; exit 1; }
	fi
	STAMP=$(date +%Y%m%d-%H%M)-${C:0:8}
	$D run --rm --user 0 -v "$VOL:/w" "$IMG" chown build:build /w
	$D run -d --name "air6-kit-$STAMP" -e FORK_COMMIT="$C" -e STAMP="$STAMP" -e AIR6_MODEM="$MODEM" \
		-v "$PWD:/kit:ro" -v "$FORK_DIR:/fork:ro" -v "$VOL:/home/build/work" "$IMG" /kit/build/build-in-container.sh >/dev/null
	echo "$STAMP" ;;
status)
	STAMP=${2:?usage: ./build.sh status STAMP}
	LOG=$($D run --rm -v "$VOL:/w:ro" "$IMG" cat "/w/kit-status/$STAMP/progress.log")
	echo "$LOG" | tail -n 5
	echo "container: $($D ps -a --filter "name=air6-kit-$STAMP" --format '{{.Status}}')"
	if echo "$LOG" | grep -q ' DONE$'; then
		echo "result: done; next: ./build.sh collect $STAMP"
	elif echo "$LOG" | grep -q ' FAILED'; then
		echo "result: failed; see: ./build.sh logs $STAMP"
	else
		echo "result: running"
	fi ;;
collect)
	$D run --rm -v "$VOL:/w:ro" "$IMG" grep -q '^.* DONE$' "/w/kit-status/$2/progress.log" || { echo "not done"; exit 1; }
	mkdir -p out && rm -rf "out/$2"
	$D run --rm --user 0 -v "$VOL:/w:ro" -v "$PWD/out:/out" "$IMG" sh -c "cp -a /w/kit-out/$2 /out/$2 && chown -R 0:0 /out/$2"
	tail -n 1 "out/$2/CHECK.txt" ;;
logs)
	STAMP=${2:?usage: ./build.sh logs STAMP}
	mkdir -p "out/logs-$STAMP"
	$D run --rm --user 0 -v "$VOL:/w:ro" -v "$PWD/out:/out" "$IMG" \
		sh -c "cp /w/kit-status/$STAMP/*.log /out/logs-$STAMP/ && chown -R 0:0 /out/logs-$STAMP"
	ls "out/logs-$STAMP"
	echo "the last step is in progress.log; its log file is named after the step" ;;
*)
	sed -n '2,18p' "$0"; exit 2 ;;
esac
