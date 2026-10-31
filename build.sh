#!/bin/bash
# Builds the OpenWrt image for the Air 6 in a Docker container. Run these commands on your Linux computer.
#   ./build.sh image                  build the Docker image that the build runs in (once)
#   ./build.sh fetch                  download the OpenWrt fork into openwrt/, at the commit in fork.lock
#   ./build.sh pull-fw [USER@]DEVICE  copy the Wi-Fi firmware from a unit running the stock firmware (once)
#   ./build.sh start [OPTIONS]        start a build in the background and print its build ID
#   ./build.sh status ID              show the progress of a build; the last line says running, done or failed
#   ./build.sh collect ID             copy a finished build to out/ID/ and print the image check result
#   ./build.sh logs ID                copy the logs of a build to out/logs-ID/ (for a failed build; an existing
#                                     out/logs-ID/ is kept: remove it to copy again)
# Optional modem support (docs/modem.md):
#   ./build.sh pull-modem [USER@]DEVICE [SLOT] | FILE
#                                     copy the modem userspace from a unit running the stock firmware (default:
#                                     the slot it does not run from) or from a saved stock root filesystem image FILE
# Options of start (any order, before DIR; details in docs/build.md):
#   --no-local-files                  leave out local/files/ (used by default)
#   --local-config                    add local/diffconfig to the build configuration (not used by default)
#   --kernel-patches                  add local/kernel-patches/*.patch to the kernel patches (not used by default)
#   --all-kmods                       build every kernel module as a package (config/all-kmods.exclude excepted)
#   --trial                           trial image: air6.trial=1 on the kernel command line; a start of a slot not
#                                     yet committed arms a timer that returns to the other slot after 10 minutes
#                                     unless 'air6-slot trial commit' runs (check 'air6-slot status' for timer=armed)
# Advanced:
#   ./build.sh start [OPTIONS] DIR [COMMIT]
#                                     build another checkout DIR of the fork, at COMMIT (default: its HEAD)
#   DOCKER_CONTEXT=NAME               use this Docker context (default: the current one; tested with rootless Docker)
#   AIR6_VOLUME=NAME                  Docker volume for downloads and the build tree (default: air6-kit-work)
#   AIR6_SSH="ssh -i KEY ..."         ssh command for pull-fw (default: ssh)
#   AIR6_MODEM=1 | VERSION            start: include the optional modem support with the files from pull-modem
# A build reads the kit, local/ and the fork checkout while it runs: do not change them until it is done or failed.
set -euo pipefail
cd "$(dirname "$0")"
D="docker${DOCKER_CONTEXT:+ --context $DOCKER_CONTEXT}"
IMG=air6-kit-builder:22.04 VOL=${AIR6_VOLUME:-air6-kit-work}
. ./fork.lock
. ./stock-firmware.lock
FW=local/firmware/mt7996
fw_missing() { echo "$STOCK_WIFI_FW" | awk 'NF == 3 { print $2 }' | while read -r n; do [ -f "$FW/$n" ] || echo "$n"; done; }
# One build per volume: the worker container carries this name and is the reservation.
WORKER=air6-kit-$VOL
# Build IDs: YYYYMMDD-HHMMSS-<fork 8> (older builds: YYYYMMDD-HHMM-<fork 8>).
valid_id() { [[ "$1" =~ ^[0-9]{8}-[0-9]{4}([0-9]{2})?-[0-9a-f]{8}$ ]] || { echo "not a build ID: $1" >&2; exit 2; }; }
# Owner for files copied out of the volume: the caller. Under rootless Docker the container's root is the caller.
owner() { if $D info -f '{{.SecurityOptions}}' 2>/dev/null | grep -q rootless; then echo 0:0; else echo "$(id -u):$(id -g)"; fi; }
vol_cat() { $D run --rm -v "$VOL:/w:ro" "$IMG" cat "/w/$1" 2>/dev/null; }
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
	shift
	O_FILES=1 O_CONFIG= O_PATCHES= O_ALLK= O_TRIAL=
	while [ $# -gt 0 ]; do
		case "$1" in
		--no-local-files) O_FILES= ;;
		--local-config) O_CONFIG=1 ;;
		--kernel-patches) O_PATCHES=1 ;;
		--all-kmods) O_ALLK=1 ;;
		--trial) O_TRIAL=1 ;;
		--*) echo "unknown option: $1" >&2; exit 2 ;;
		*) break ;;
		esac
		shift
	done
	[ -z "$(fw_missing)" ] || { echo "Wi-Fi firmware missing in $FW/: run './build.sh pull-fw [USER@]DEVICE' first" >&2; exit 1; }
	[ $# -le 2 ] || { echo "start: too many arguments: $*" >&2; exit 2; }
	if [ $# -ge 1 ]; then
		FORK_DIR=$(cd "$1" && pwd) REF=${2:-HEAD}
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
	# Selected inputs must exist and not be empty; unselected ones are named, not used.
	has_lines() { [ -f "$1" ] && grep -q '[^[:space:]]' "$1"; }
	if [ -n "$O_CONFIG" ]; then
		has_lines local/diffconfig || { echo "--local-config: local/diffconfig is missing or empty" >&2; exit 1; }
	elif [ -e local/diffconfig ]; then
		echo "note: local/diffconfig is present and not used (add --local-config to use it)" >&2
	fi
	if [ -n "$O_PATCHES" ]; then
		ls local/kernel-patches/*.patch > /dev/null 2>&1 || { echo "--kernel-patches: no local/kernel-patches/*.patch" >&2; exit 1; }
		for p in local/kernel-patches/*.patch; do
			[[ "$(basename "$p")" =~ ^[0-9]+-[A-Za-z0-9._+-]+\.patch$ ]] || { echo "--kernel-patches: bad name $p (NNN-name.patch)" >&2; exit 1; }
			[ -s "$p" ] || { echo "--kernel-patches: $p is empty" >&2; exit 1; }
		done
	elif [ -d local/kernel-patches ]; then
		echo "note: local/kernel-patches/ is present and not used (add --kernel-patches to use it)" >&2
	fi
	if [ -n "$O_ALLK" ]; then
		bad=$(grep -v -E '^[[:space:]]*(#.*)?$' config/all-kmods.exclude | grep -v -E '^[A-Za-z0-9._+-]+ # [^[:space:]].*$' || true)
		[ -z "$bad" ] || { echo "config/all-kmods.exclude: malformed line(s) (\"package # reason\"):" >&2; echo "$bad" >&2; exit 1; }
	fi
	if [ -n "$O_FILES" ] && [ -d local/files ]; then
		notes=$(cd local/files && find . \( -type f -o -type l \) | sed 's|^\./||' | LC_ALL=C sort | grep -E \
			'^(lib/modules/|lib/firmware/|etc/modules\.conf$|etc/modules\.d/|etc/init\.d/|etc/rc\.d/|etc/uci-defaults/|lib/apk/|etc/apk/)' || true)
		[ -z "$notes" ] || { echo "note: local/files/ changes more than settings (listed in PROVENANCE):" >&2; echo "$notes" | sed 's/^/  /' >&2; }
	fi
	# The kit's build inputs as they are now (empty: those of the kit commit); the worker compares at the end.
	KIT_START=$(build/kit-inputs.sh "$PWD")
	ID=$(date +%Y%m%d-%H%M%S)-${C:0:8}
	TOKEN=$(tr -d '-' < /proc/sys/kernel/random/uuid)
	# Reserve the volume: create the worker before touching the volume, start it by the ID Docker returned.
	if cur=$($D inspect -f '{{.Id}} {{.State.Status}} {{index .Config.Labels "air6.run"}}' "$WORKER" 2>/dev/null); then
		read -r cid st run <<< "$cur"
		case "$st" in
		exited|dead) $D rm "$cid" > /dev/null 2>&1 || true ;;
		*)
			echo "volume $VOL is in use: container $WORKER ($cid, build ${run:-unknown}) is $st" >&2
			[ "$st" = created ] && echo "if that build never started, check it and remove it with: docker rm $cid" >&2
			exit 1 ;;
		esac
	fi
	legacy=$($D ps -a --filter "volume=$VOL" --filter status=running --filter status=created --filter status=paused \
		--filter status=restarting --format '{{.Names}}' | grep -vx "$WORKER" || true)
	[ -z "$legacy" ] || { echo "volume $VOL is in use by: $legacy" >&2; exit 1; }
	cid=$($D create --name "$WORKER" --label "air6.run=$ID" --label "air6.token=$TOKEN" --label "air6.volume=$VOL" \
		-e FORK_COMMIT="$C" -e FORK_LOCK_COMMIT="$FORK_COMMIT" -e RUN_ID="$ID" -e RUN_TOKEN="$TOKEN" \
		-e AIR6_MODEM="$MODEM" -e O_FILES="$O_FILES" -e O_CONFIG="$O_CONFIG" -e O_PATCHES="$O_PATCHES" \
		-e O_ALLK="$O_ALLK" -e O_TRIAL="$O_TRIAL" -e KIT_START="$KIT_START" -e KIT_HEAD_START="$(git rev-parse HEAD)" \
		-e START_TIME="$(date -u '+%F %T')" \
		-v "$PWD:/kit:ro" -v "$FORK_DIR:/fork:ro" -v "$VOL:/home/build/work" "$IMG" /kit/build/build-in-container.sh) ||
		{ echo "volume $VOL is in use (could not create $WORKER)" >&2; exit 1; }
	if ! $D run --rm --user 0 -v "$VOL:/w" "$IMG" chown build:build /w || ! $D start "$cid" > /dev/null; then
		$D rm "$cid" > /dev/null 2>&1 || true
		echo "could not start the build" >&2; exit 1
	fi
	echo "do not change the kit, local/ or the fork checkout until './build.sh status $ID' says done or failed" >&2
	echo "$ID" ;;
status)
	ID=${2:?usage: ./build.sh status ID}; valid_id "$ID"
	LOG=$(vol_cat "kit-status/$ID/progress.log") || { echo "no build $ID in volume $VOL" >&2; exit 1; }
	echo "$LOG" | tail -n 5
	TOKEN=$(vol_cat "kit-status/$ID/RUN_TOKEN" || true)
	if [ -n "$TOKEN" ]; then
		cs=$($D ps -a --filter "label=air6.token=$TOKEN" --format '{{.Status}}')
	else
		cs=$($D ps -a --filter "name=^air6-kit-$ID\$" --format '{{.Status}}')
	fi
	echo "container: ${cs:-none (removed; the saved status above is final)}"
	if echo "$LOG" | grep -q ' DONE$'; then
		echo "result: done; next: ./build.sh collect $ID"
	elif echo "$LOG" | grep -q ' FAILED'; then
		echo "result: failed; see: ./build.sh logs $ID"
	elif [ -z "$cs" ] || echo "$cs" | grep -q '^Exited'; then
		echo "result: stopped without DONE or FAILED; see: ./build.sh logs $ID"
	else
		echo "result: running"
	fi ;;
collect)
	ID=${2:?usage: ./build.sh collect ID}; valid_id "$ID"
	vol_cat "kit-status/$ID/progress.log" | grep -q ' DONE$' || { echo "build $ID is not done" >&2; exit 1; }
	mkdir -p out
	STAGE=$(mktemp -d "out/.stage-$ID-XXXXXX")
	trap 'rm -rf "$STAGE"' EXIT
	$D run --rm --user 0 -v "$VOL:/w:ro" -v "$PWD/$STAGE:/stage" "$IMG" \
		sh -c "cp -a /w/kit-out/$ID/. /stage/ && chown -R $(owner) /stage" ||
		{ echo "could not copy build $ID" >&2; exit 1; }
	verify() { (cd "$1" && sha256sum -c --quiet SHA256SUMS && { [ ! -f PACKAGES.sha256 ] || sha256sum -c --quiet PACKAGES.sha256; }); }
	verify "$STAGE" || { echo "the copy of $ID does not match its own hashes" >&2; exit 1; }
	NEW=$(cat "$STAGE/RUN_TOKEN" 2>/dev/null || true)
	exec 9> "out/.$ID.lock"
	flock 9
	if [ ! -e "out/$ID" ]; then
		chmod 755 "$STAGE"
		mv -T "$STAGE" "out/$ID"
	else
		OLD=$(cat "out/$ID/RUN_TOKEN" 2>/dev/null || true)
		if [ -z "$NEW" ] || [ "$OLD" != "$NEW" ]; then
			echo "out/$ID exists and belongs to another build; nothing changed" >&2; exit 1
		fi
		# Same build only if every entry matches the fresh copy: type, mode, link target and content (links not followed).
		meta() { (cd "$1" && find . -printf '%y %m %l %p\n' | LC_ALL=C sort); }
		{ [ "$(meta "$STAGE")" = "$(meta "out/$ID")" ] && diff -r -q --no-dereference "$STAGE" "out/$ID" > /dev/null; } ||
			{ echo "out/$ID is this build but its files differ from the build; nothing changed" >&2; exit 1; }
		echo "out/$ID already holds this build" >&2
	fi
	tail -n 1 "out/$ID/CHECK.txt" ;;
logs)
	ID=${2:?usage: ./build.sh logs ID}; valid_id "$ID"
	TOKEN=$(vol_cat "kit-status/$ID/RUN_TOKEN" || true)
	mkdir -p out
	STAGE=$(mktemp -d "out/.stage-logs-$ID-XXXXXX")
	trap 'rm -rf "$STAGE"' EXIT
	$D run --rm --user 0 -v "$VOL:/w:ro" -v "$PWD/$STAGE:/stage" "$IMG" \
		sh -c "cp /w/kit-status/$ID/*.log /stage/ && chown -R $(owner) /stage"
	[ -z "$TOKEN" ] || echo "$TOKEN" > "$STAGE/RUN_TOKEN"
	chmod 755 "$STAGE"
	# An export is never replaced (a replacement could lose it if interrupted); the lock makes check and move one step.
	exec 9> "out/.logs-$ID.lock"
	flock 9
	if [ -e "out/logs-$ID" ]; then
		OLD=$(cat "out/logs-$ID/RUN_TOKEN" 2>/dev/null || true)
		if [ -z "$TOKEN" ] || [ "$OLD" != "$TOKEN" ]; then
			echo "out/logs-$ID exists and is not from this build; nothing changed" >&2; exit 1
		fi
		echo "out/logs-$ID already holds logs of this build, exported earlier; nothing changed (remove it to export again)" >&2
		exit 1
	fi
	mv -T "$STAGE" "out/logs-$ID"
	ls "out/logs-$ID"
	echo "the last step is in progress.log; its log file is named after the step" ;;
*)
	sed -n '2,30p' "$0"; exit 2 ;;
esac
