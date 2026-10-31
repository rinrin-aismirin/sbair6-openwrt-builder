#!/bin/bash
# Run on your computer: works on the Air 6 over SSH (ssh command from $AIR6_SSH, default "ssh"). See README.md.
#   ./device.sh status DEVICE           show the booted slot, the boot control bytes and (OpenWrt) the trial timer,
#                                       failed updates and the last sysupgrade record
#   ./device.sh install DEVICE STAMP    (stock firmware) upload out/STAMP and install it into the other slot
#   ./device.sh upgrade DEVICE STAMP [--no-config]
#                                       (OpenWrt) sysupgrade to out/STAMP: write it into the other slot, keeping the
#                                       settings unless --no-config, and reboot into it. Overwriting a slot that holds
#                                       the stock firmware needs a confirmed stock-backup that still matches the slot
#   ./device.sh upgrade-check DEVICE STAMP
#                                       (OpenWrt, after the reboot) compare the unit's sysupgrade record with the last
#                                       upgrade request for out/STAMP
#   ./device.sh reboot DEVICE           reboot the unit
#   ./device.sh trial-commit DEVICE     (OpenWrt, trial image) keep the trial slot: mark it successful, stop the
#                                       10-minute return to the other slot
#   ./device.sh set-active DEVICE SLOT  (OpenWrt) boot slot a or b next time (it must be marked successful); then
#                                       ./device.sh reboot DEVICE
#   ./device.sh switch DEVICE STAMP     (stock firmware) boot again into out/STAMP, already in the other slot
#   ./device.sh nv-backup DEVICE        (OpenWrt with modem support) save the NV partitions to out/air6-nv-<time>.tar.gz
#   ./device.sh stock-backup DEVICE [SLOT]
#                                       (OpenWrt) save the stock firmware slot SLOT (default: the other slot) to
#                                       out/stock/air6-stock-<slot>-<time>-<id>.tar, check it, then confirm it on the
#                                       unit (sysupgrade needs the confirmed backup)
#   ./device.sh restore-stock DEVICE FILE
#                                       (OpenWrt) check FILE (from stock-backup), write mcf1, mcf2, boot and rootfs
#                                       of its slot from it and boot that slot next time as a trial; then
#                                       ./device.sh reboot DEVICE
# DEVICE is what ssh accepts, for example root@192.168.1.1. Nothing reboots unless the command says so.
set -euo pipefail
cd "$(dirname "$0")"
SSH=${AIR6_SSH:-ssh}
run() { $SSH "$DEV" "$@"; }
kind() {
	run '[ -f /lib/upgrade/bootctrl.sh ] && echo stock || { [ -x /usr/sbin/air6-slot ] && echo openwrt; } ||
		{ [ -x /usr/sbin/air6-abguard ] && echo openwrt-old; } || echo other'
}
old() { echo "$DEV runs an older OpenWrt image (air6-abguard): use the kit version that built it" >&2; exit 1; }
need() {
	k=$(kind)
	[ "$k" = "$1" ] && return 0
	[ "$1" = openwrt ] && [ "$k" = openwrt-old ] && old
	[ "$1" = stock ] && echo "$DEV is not running the stock firmware" >&2 || echo "$DEV is not running OpenWrt" >&2
	exit 1
}
sha() { grep " $1\$" "out/$STAMP/SHA256SUMS" | cut -d' ' -f1; }
stamp() {
	STAMP=${1:?STAMP missing (a directory name under out/)}
	[ -f "out/$STAMP/CHECK.txt" ] || { echo "out/$STAMP/CHECK.txt not found" >&2; exit 1; }
	[ "$(tail -n 1 "out/$STAMP/CHECK.txt")" = "RESULT: PASS" ] || { echo "out/$STAMP did not pass the image check" >&2; exit 1; }
}

# Stock slot archives, as made by air6-stock on the unit (format air6-stock-backup/1; see its header).
STOCK_PARTS="connsys_gnss md1img md1dsp spmfw pi_img dpm medmcu sspm mcupm lk tee mcf1 mcf2 boot rootfs"
STOCK_META_KEYS="format backup_id slot unit created stock_version md1img_version"
STOCK_RUN_RE='^/tmp/air6-stock/run\.[A-Za-z0-9]{6}$'
# stock_members SLOT: the archive members of SLOT, in archive order.
stock_members() { local p; printf '%s\n' META SHA256SUMS; for p in $STOCK_PARTS; do echo "${p}_$1.img"; done; }
# stock_check FILE SLOT DIR: FILE is a complete archive of SLOT (of any one slot when SLOT is empty), extracted into
# the empty private directory DIR and checked there. Sets A_SLOT, A_ID, A_DIGEST (sha256 of SHA256SUMS). Prints the
# reason and returns 1 when not. META is parsed, never sourced.
stock_check() {
	local f=$1 d=$3 s names m want
	names=$(LC_ALL=C tar -tf "$f" 2>/dev/null) || { echo "$f: not a complete tar archive" >&2; return 1; }
	s=$(printf '%s\n' "$names" | sed -n '3s/^connsys_gnss_\([ab]\)\.img$/\1/p')
	[ -n "$s" ] && [ "$names" = "$(stock_members "$s")" ] ||
		{ echo "$f: the members are not exactly META, SHA256SUMS and the 15 images of one slot, in order" >&2; return 1; }
	[ -z "$2" ] || [ "$2" = "$s" ] || { echo "$f: holds slot $s, not slot $2" >&2; return 1; }
	m=$(LC_ALL=C tar -tvf "$f" 2>/dev/null | cut -c1 | tr -d '\n') || m=
	[ "$m" = "-----------------" ] || { echo "$f: not every member is a regular file" >&2; return 1; }
	# shellcheck disable=SC2046 # the member names are fixed words
	tar -C "$d" -xf "$f" --no-same-owner --no-same-permissions -- $(stock_members "$s") 2>/dev/null ||
		{ echo "$f: cannot be extracted" >&2; return 1; }
	[ "$(ls -A "$d" | LC_ALL=C sort)" = "$(stock_members "$s" | LC_ALL=C sort)" ] ||
		{ echo "$f: extracted something else than its members" >&2; return 1; }
	for m in $(stock_members "$s"); do
		[ -f "$d/$m" ] && [ ! -L "$d/$m" ] || { echo "$f: $m is not a regular file" >&2; return 1; }
	done
	# SHA256SUMS: "<sha256>  <member>" for META and the 15 images, in archive order, nothing else.
	LC_ALL=C awk -v slot="$s" -v parts="$STOCK_PARTS" '
		BEGIN { np = split(parts, P, " "); N[1] = "META"; for (i = 1; i <= np; i++) N[i + 1] = P[i] "_" slot ".img"; total = np + 1 }
		{
			if (NR > total) { bad = 1; exit }
			h = substr($0, 1, 64)
			if (length(h) != 64 || h ~ /[^0-9a-f]/ || substr($0, 65) != "  " N[NR]) { bad = 1; exit }
		}
		END { exit (bad || NR != total) }' "$d/SHA256SUMS" || { echo "$f: SHA256SUMS is malformed" >&2; return 1; }
	(cd "$d" && sha256sum -c --quiet SHA256SUMS) >&2 || { echo "$f: a member does not match SHA256SUMS" >&2; return 1; }
	# META: the same rules as air6-stock's meta_check (key order, values, slot).
	LC_ALL=C awk -v slot="$s" -v keys="$STOCK_META_KEYS" -v parts="$STOCK_PARTS" -v format=air6-stock-backup/1 '
		function hex(v, n) { return length(v) == n && v !~ /[^0-9a-f]/ }
		BEGIN {
			n = split(keys, K, " "); np = split(parts, P, " ")
			for (i = 1; i <= np; i++) K[n + i] = "size_" P[i] "_" slot
			total = n + np
		}
		{
			if (NR > total) { bad = 1; exit }
			eq = index($0, "="); k = substr($0, 1, eq - 1); v = substr($0, eq + 1)
			if (eq < 2 || k != K[NR]) { bad = 1; exit }
			if (k == "format") ok = (v == format)
			else if (k == "backup_id") ok = hex(v, 32)
			else if (k == "slot") ok = (v == slot)
			else if (k == "unit") {
				ok = (split(v, U, ",") == 4)
				for (i = 1; i <= 4; i++) if (!hex(U[i], 32)) ok = 0
				if (length(v) != 131) ok = 0
			}
			else if (k == "created") ok = (v ~ /^[0-9]+-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/)
			else if (k == "stock_version" || k == "md1img_version")
				ok = (v != "" && length(v) <= 80 && v !~ /[^0-9A-Za-z._+-]/)
			else ok = (v ~ /^[1-9][0-9]*$/ && length(v) <= 15)
			if (!ok) { bad = 1; exit }
		}
		END { exit (bad || NR != total) }' "$d/META" || { echo "$f: META is malformed or not for slot $s" >&2; return 1; }
	for m in $STOCK_PARTS; do
		want=$(sed -n "s/^size_${m}_$s=//p" "$d/META")
		[ "$(stat -c %s "$d/${m}_$s.img")" = "$want" ] || { echo "$f: ${m}_$s.img is not $want bytes as META says" >&2; return 1; }
	done
	A_SLOT=$s
	A_ID=$(sed -n '2s/^backup_id=//p' "$d/META")
	A_DIGEST=$(sha256sum < "$d/SHA256SUMS" | cut -c1-64)
}
need_stock_tool() {
	run '[ -x /usr/sbin/air6-stock ]' || { echo "this image has no /usr/sbin/air6-stock (build a newer image with the kit)" >&2; exit 1; }
}
# booted: BOOTED = the slot the unit runs from (air6-slot current).
booted() {
	BOOTED=$(run 'air6-slot current' || true)
	case "$BOOTED" in a|b) ;; *) echo "cannot read the booted slot of $DEV (air6-slot current: '$BOOTED')" >&2; exit 1 ;; esac
}
# stock_dir: out/stock exists, is a real directory owned by the user and closed to everyone else.
stock_dir() {
	[ ! -L out/stock ] || { echo "out/stock is a symbolic link; refusing" >&2; exit 1; }
	mkdir -p out
	[ -e out/stock ] || mkdir -m 700 out/stock
	[ -d out/stock ] && [ ! -L out/stock ] && [ -O out/stock ] ||
		{ echo "out/stock is not a directory owned by you; refusing" >&2; exit 1; }
	[ "$(stat -c %a out/stock)" = 700 ] || { echo "out/stock is not private (mode $(stat -c %a out/stock)); chmod 700 out/stock" >&2; exit 1; }
}

cmd=${1:-} DEV=${2:-}
[ -n "$cmd" ] && [ -n "$DEV" ] || { sed -n '2,28p' "$0"; exit 2; }
case "$cmd" in
status)
	case "$(kind)" in
	stock) run 'sh -s' < scripts/device/read_ab.sh ;;
	openwrt) run 'air6-slot status' ;;
	openwrt-old) old ;;
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
upgrade)
	stamp "${3:-}"
	case "${4:-}" in '') KEEP= ;; --no-config) KEEP=-n ;; *) echo "upgrade: unknown option ${4}" >&2; exit 2 ;; esac
	need openwrt
	[ -f "out/$STAMP/sysupgrade.bin" ] || { echo "out/$STAMP/sysupgrade.bin not found (built by kits from this version on)" >&2; exit 1; }
	run '[ -f /lib/air6/upgrade.sh ]' || { echo "$DEV runs an image without sysupgrade support: install the new build from the stock firmware once" >&2; exit 1; }
	h=$(sha sysupgrade.bin)
	# One private upload file per request: the check and the run use exactly the file this request uploaded.
	rp=$(run 'mktemp /tmp/air6-sysupgrade.XXXXXX') || { echo "cannot create an upload file on the unit" >&2; exit 1; }
	case "$rp" in /tmp/air6-sysupgrade.??????) ;; *) echo "unexpected upload path '$rp'" >&2; exit 1 ;; esac
	echo "uploading sysupgrade.bin to $rp"
	run "cat > $rp" < "out/$STAMP/sysupgrade.bin"
	got=$(run "sha256sum $rp" | cut -d' ' -f1)
	[ "$got" = "$h" ] || { echo "upload damaged (sha256 $got, expected $h)" >&2; exit 1; }
	# The unit checks the package and its own state; nothing is written when this fails.
	run "sysupgrade -T $KEEP $rp" || { run "rm -f $rp"; echo "the unit refused the package (see above); nothing was written" >&2; exit 1; }
	bid=$(run 'cat /proc/sys/kernel/random/boot_id')
	slot=$(run 'air6-slot current')
	req=out/$STAMP/upgrade-request-$(date +%Y%m%d-%H%M%S)
	printf 'device=%s\nboot_id=%s\nfrom=%s\nimage=%s\nconfig=%s\n' "$DEV" "$bid" "$slot" "$h" "${KEEP:-keep}" > "$req"
	run "(sleep 1; sysupgrade $KEEP $rp) </dev/null >/dev/null 2>&1 &"
	echo "sysupgrade request sent (request recorded in $req). Whether the unit admitted it shows in its record."
	echo "The unit stops its services, writes slot $( [ "$slot" = a ] && echo b || echo a ) and reboots into it (1 to 3 minutes)."
	echo "Then run: ./device.sh upgrade-check $DEV $STAMP"
	echo "If it does not come back and the power LED blinks red, see docs/troubleshooting.md (sysupgrade stopped)." ;;
upgrade-check)
	stamp "${3:-}"
	need openwrt
	req=$(ls -1 out/$STAMP/upgrade-request-* 2>/dev/null | tail -n 1)
	[ -n "$req" ] || { echo "no upgrade request recorded for out/$STAMP" >&2; exit 1; }
	val() { sed -n "s/^$1=//p" "$req"; }
	lu=$(run 'cat /etc/air6-slot/last-upgrade 2>/dev/null' || true)
	booted=$(run 'air6-slot current')
	# The root file system must be the booted slot's rootfs (an image with another root= in its DT boots the same
	# rootfs from both slots).
	rootc=$(run '. /lib/air6/bootctrl.sh; bc_init >/dev/null 2>&1 || exit 2; bc_root_check' 2>&1; echo "rc=$?")
	run 'air6-slot status'
	echo "--- request $req: from slot $(val from), boot $(val boot_id), image $(val image)"
	begin=$(printf '%s\n' "$lu" | grep ' phase=begin ' | head -n 1)
	endl=$(printf '%s\n' "$lu" | grep ' end=1 ' | tail -n 1)
	if [ -z "$begin" ] || ! printf '%s\n' "$begin" | grep -q " boot_id=$(val boot_id)\( \|$\)"; then
		# No record of this request on the running slot (the record is kept by the slot that boots after stage2: if
		# that was the new slot and the unit came back, the record is there; a cold boot loses it). What the boot
		# control bytes, shared by both slots, still show:
		st=$(run 'air6-slot status')
		tgt=$( [ "$(val from)" = a ] && echo b || echo a )
		tline=$(printf '%s\n' "$st" | grep "^slot $tgt: ")
		tsucc=$(printf '%s\n' "$tline" | sed -n 's/.* success=\([0-9a-f]*\).*/\1/p')
		tretry=$(printf '%s\n' "$tline" | sed -n 's/.* retry=\([0-9a-f]*\).*/\1/p')
		echo "result: UNKNOWN - the unit has no record of this request. Booted slot now: $booted."
		if [ "$booted" = "$(val from)" ] && [ "$tsucc" = 00 ]; then
			if printf '%s\n' "$st" | grep -q " slot=$tgt .* success=00"; then
				echo "seen in the status: slot $tgt is not marked good and is listed under 'failed updates' (it reached the"
				echo "bootloader's retry limit before being marked good; an uncommitted trial image rebooted twice gives the"
				echo "same entry, and the entry may be from an earlier attempt). The result of this request stays unknown."
			elif [ "$tretry" != 00 ]; then
				echo "seen in the status: slot $tgt is not marked good, retry $tretry (it was selected for a boot after the"
				echo "write; whether it started, and where its record is, are not known). The result of this request stays unknown."
			else
				echo "seen in the status: slot $tgt is not marked good; whether it was started is unknown."
			fi
		elif [ "$booted" != "$(val from)" ]; then
			echo "seen in the status: the unit runs slot $booted, not the slot the request came from. Which image it runs and"
			echo "the result of this request are not known (no record, for example after a power cut): check root=, policy,"
			echo "timer and that it works before relying on it."
		fi
		exit 1
	fi
	state=$(printf '%s\n' "$endl" | sed -n 's/.* state=\([a-z]*\).*/\1/p')
	img=$(printf '%s\n' "$endl" | sed -n 's/.* image=\([0-9a-f]*\).*/\1/p')
	case "$state" in
	written)
		[ "$img" = "$(val image)" ] || { echo "result: MISMATCH - the record's image $img is not the requested one"; exit 1; }
		if [ "$booted" != "$(val from)" ] && [ "${rootc##*rc=}" != 0 ]; then
			echo "result: written, the unit booted slot $booted, but its root file system is not rootfs_$booted"
			echo "(${rootc%rc=*}); the image's device tree root= is wrong. Do not upgrade again from this state."
			exit 1
		elif [ "$booted" != "$(val from)" ]; then
			echo "result: written, and the unit runs the new slot $booted on rootfs_$booted (a normal image is marked good once start-up has finished; a trial image needs trial-commit within 10 minutes: see status)"
		else
			echo "result: written (the write finished), but the unit runs the old slot $booted again. Why is not known"
			echo "here: an uncommitted trial image, a switch back, or failed starts (see 'failed updates' and the status above)."
			exit 1
		fi ;;
	refused|failed)
		echo "result: $state - nothing was activated; slot $booted (the old one) stays. The record lines above say why."
		exit 1 ;;
	*)
		echo "result: UNKNOWN - the record of this request is incomplete (state '${state:-none}')"
		exit 1 ;;
	esac ;;
reboot)
	run 'sync; (sleep 1; reboot) >/dev/null 2>&1 &'
	echo "rebooting" ;;
trial-commit)
	need openwrt
	run 'air6-slot trial commit' ;;
set-active)
	SLOT=${3:-}
	case "$SLOT" in a|b) ;; *) echo "set-active: SLOT must be a or b" >&2; exit 2 ;; esac
	need openwrt
	run "air6-slot set-active $SLOT"
	echo "next: ./device.sh reboot $DEV" ;;
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
stock-backup)
	SLOT=${3:-}
	case "$SLOT" in ''|a|b) ;; *) echo "stock-backup: SLOT must be a or b" >&2; exit 2 ;; esac
	need openwrt; need_stock_tool; booted
	if [ -z "$SLOT" ]; then [ "$BOOTED" = a ] && SLOT=b || SLOT=a; fi
	[ "$SLOT" != "$BOOTED" ] || { echo "slot $SLOT is the booted slot; back up the other slot" >&2; exit 1; }
	# The archive holds unit-specific data: private from the moment it is created.
	umask 077
	stock_dir
	RECV= XD=
	trap 'rm -rf -- ${RECV:+"$RECV"} ${XD:+"$XD"}' EXIT
	trap 'exit 130' INT; trap 'exit 143' TERM HUP
	RECV=$(mktemp out/stock/.receive.XXXXXX)
	XD=$(mktemp -d out/stock/.check.XXXXXX)
	echo "reading slot $SLOT of $DEV (15 partitions)"
	rc=0; run "air6-stock backup $SLOT -" > "$RECV" || rc=$?
	[ "$rc" = 0 ] || { echo "backup failed (rc $rc); nothing saved, not confirmed" >&2; exit 1; }
	H=$(sha256sum < "$RECV" | cut -c1-64)
	stock_check "$RECV" "$SLOT" "$XD" || { echo "the received archive failed the checks; nothing saved, not confirmed" >&2; exit 1; }
	rm -rf -- "$XD"; XD=
	OUT=out/stock/air6-stock-$SLOT-$(date +%Y%m%d-%H%M%S)-${A_ID:0:8}.tar
	# A hard link never replaces an existing file.
	ln -- "$RECV" "$OUT" 2>/dev/null || { echo "cannot save $OUT (exists already?); nothing saved, not confirmed" >&2; exit 1; }
	rm -f -- "$RECV"; RECV=
	chmod 600 "$OUT"
	sync
	if [ "$(sha256sum < "$OUT" | cut -c1-64)" != "$H" ]; then
		rm -f -- "$OUT"
		echo "$OUT does not read back as received; removed, not confirmed" >&2
		exit 1
	fi
	echo "saved $OUT"
	echo "  slot $SLOT, backup_id $A_ID"
	echo "  digest $A_DIGEST"
	echo "  $(stat -c %s "$OUT") bytes"
	echo "The file holds unit-specific data: keep it private and keep a safe copy. A confirmed backup on the unit does not"
	echo "prove that this file still exists."
	rc=0; run "air6-stock confirm $SLOT $A_ID $A_DIGEST" || rc=$?
	if [ "$rc" != 0 ]; then
		echo "the backup is NOT confirmed on the unit (rc $rc): sysupgrade refuses to overwrite slot $SLOT until it is." >&2
		echo "The file is kept. Retry the confirm (repeating it is safe):" >&2
		echo "  ssh $DEV air6-stock confirm $SLOT $A_ID $A_DIGEST" >&2
		exit 1
	fi
	echo "confirmed on the unit" ;;
restore-stock)
	FILE=${3:-}
	[ -n "$FILE" ] || { echo "restore-stock: FILE missing (an archive from stock-backup)" >&2; exit 2; }
	[ -f "$FILE" ] || { echo "$FILE is not a file" >&2; exit 1; }
	need openwrt; need_stock_tool
	umask 077
	XD=
	trap 'rm -rf -- ${XD:+"$XD"}' EXIT
	trap 'exit 130' INT; trap 'exit 143' TERM HUP
	XD=$(mktemp -d)
	stock_check "$FILE" "" "$XD" || { echo "$FILE failed the checks; nothing sent to the unit" >&2; exit 1; }
	S=$A_SLOT
	booted
	[ "$S" != "$BOOTED" ] ||
		{ echo "$FILE is a backup of slot $S, the booted slot; boot the other slot first (nothing sent to the unit)" >&2; exit 1; }
	echo "$FILE: backup $A_ID of slot $S ($(sed -n '5s/^created=//p' "$XD/META"), stock $(sed -n '6s/^stock_version=//p' "$XD/META")) checked"
	DIR=$(run 'air6-stock stage') || { echo "air6-stock stage failed; nothing changed" >&2; exit 1; }
	# The path goes into remote commands: only the exact form that stage makes.
	[[ $DIR =~ $STOCK_RUN_RE ]] || { echo "unexpected run directory from air6-stock stage: $(printf %q "$DIR"); nothing changed" >&2; exit 1; }
	for m in META SHA256SUMS "mcf1_$S.img" "mcf2_$S.img" "boot_$S.img" "rootfs_$S.img"; do
		echo "uploading $m"
		run "cat > '$DIR/$m'" < "$XD/$m" ||
			{ echo "uploading $m failed; nothing written (the run directory $DIR on the unit is left unused)" >&2; exit 1; }
	done
	rc=0; run "air6-stock restore $S '$DIR'" || rc=$?
	if [ "$rc" = 255 ]; then
		echo "the SSH connection failed during the restore; asking the unit for the result of $DIR" >&2
		rrc=0; res=$(run "air6-stock result '$DIR'") || rrc=$?
		[ -z "$res" ] || printf '%s\n' "$res"
		st=$(printf '%s\n' "$res" | sed -n '/^state=/{s///p;q;}')
		r=$(printf '%s\n' "$res" | sed -n '/^rc=/{s///p;q;}')
		case "$r" in ''|*[!0-9]*) r=x ;; esac
		case "$rrc:$st:$r" in
		0:done:0|0:failed:[0-9]*|0:refused:[0-9]*) rc=$r ;;
		*)
			echo "the outcome is not known yet (result rc $rrc). Ask again later, before anything else on that slot:" >&2
			echo "  ssh $DEV air6-stock result $DIR" >&2 ;;
		esac
	fi
	case "$rc" in
	0)
		echo "slot $S is the next boot slot as a trial (retry preset 02): if the restored stock does not come up after a few"
		echo "attempts, the preloader returns to slot $BOOTED"
		echo "next: ./device.sh reboot $DEV" ;;
	3|4|5) echo "restore not done (rc $rc): nothing was written" >&2 ;;
	6)
		echo "restore stopped after a change was started (rc 6). Before anything else, read its outcome lines above (also" >&2
		echo "shown by: ssh $DEV air6-stock result $DIR) and check ./device.sh status $DEV." >&2
		echo "Run restore-stock again only if the outcome says slot $S stays unsuccessful (not selectable) or that the boot" >&2
		echo "control record is unchanged." >&2 ;;
	esac
	exit "$rc" ;;
*)
	sed -n '2,28p' "$0"; exit 2 ;;
esac
