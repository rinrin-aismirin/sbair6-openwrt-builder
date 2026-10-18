#!/bin/bash
# Builds the OpenWrt image for the Air 6 in a Docker container. Run these commands on your Linux computer.
#   ./build.sh image                  build the Docker image that the build runs in (once)
#   ./build.sh fetch                  download the OpenWrt fork into openwrt/, at the commit in fork.lock
#   ./build.sh pull-fw [USER@]DEVICE  copy the Wi-Fi firmware from a unit running the stock firmware (once)
#   ./build.sh start                  start a build in the background and print its build ID (STAMP)
#   ./build.sh status STAMP           show the progress of a build; the last line says running, done or failed
#   ./build.sh collect STAMP          copy a finished build to out/STAMP/ and print the image check result
#   ./build.sh logs STAMP             copy the logs of a build to out/logs-STAMP/ (for a failed build)
# Advanced:
#   ./build.sh start DIR [COMMIT]     build another checkout DIR of the fork, at COMMIT (default: its HEAD)
#   DOCKER_CONTEXT=NAME               use this Docker context (default: the current one; tested with rootless Docker)
#   AIR6_VOLUME=NAME                  Docker volume for downloads and the build tree (default: air6-kit-work)
#   AIR6_SSH="ssh -i KEY ..."         ssh command for pull-fw (default: ssh)
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
start)
	[ -z "$(fw_missing)" ] || { echo "Wi-Fi firmware missing in $FW/: run './build.sh pull-fw [USER@]DEVICE' first" >&2; exit 1; }
	if [ $# -ge 2 ]; then
		FORK_DIR=$(cd "$2" && pwd) REF=${3:-HEAD}
	else
		FORK_DIR=$PWD/openwrt REF=$FORK_COMMIT
		[ -d "$FORK_DIR/.git" ] || { echo "openwrt/ not found; run './build.sh fetch' first" >&2; exit 1; }
	fi
	C=$(git -C "$FORK_DIR" rev-parse --verify "$REF^{commit}")
	STAMP=$(date +%Y%m%d-%H%M)-${C:0:8}
	$D run --rm --user 0 -v "$VOL:/w" "$IMG" chown build:build /w
	$D run -d --name "air6-kit-$STAMP" -e FORK_COMMIT="$C" -e STAMP="$STAMP" \
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
	sed -n '2,14p' "$0"; exit 2 ;;
esac
