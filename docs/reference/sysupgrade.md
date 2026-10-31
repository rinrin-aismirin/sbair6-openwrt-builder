# sysupgrade: updating OpenWrt into the other slot

This page specifies how an update from OpenWrt works on the Air 6: the package, the checks, the write, how a run ends
and the record it leaves. The steps to run are in [2-keep.md](../2-keep.md#2-write-openwrt-into-the-stock-slot) (the
first update, over the stock slot) and [3-update.md](../3-update.md); the slots and the boot control record are
explained in [boot-control.md](boot-control.md).

## What it writes

sysupgrade always writes the other slot, the one OpenWrt is not running from. It writes three things there, then
selects that slot for the next boot (X is the other slot, `a` or `b`):

- `boot_X`: the signed boot image of the build (32 MiB).
- `rootfs_X`: the squashfs of the build, from the start of the partition.
- The settings, inside `rootfs_X` behind the squashfs ([Settings](#settings)).

Apart from the boot control record in `misc`, nothing else is written: not the running slot, not the other 13
partitions of the slot, not the shared partitions ([partitions.md](partitions.md#who-writes-what)). The previous
build stays in the running slot as the way back.

- `sysupgrade -s` (stay on the current partition) passes the check but is refused at the
  [admission](#the-write), after the services were stopped: nothing is written and the unit reboots into the running
  slot.
- There is no force path: every refusal of the [check](#checks-before-anything-is-written) returns 74, which `-F`
  does not override.
- The package check does not compare the build with the one that runs: the same build can be written again. This was
  done on unit 1 over the stock slot, on 2026-10-31 with a build whose device tree `root=` was wrong (fixed since),
  and on 2026-11-01 with the current build, a trial image ([status.md](status.md)).

The code is `/lib/upgrade/platform.sh` (fork, `target/linux/mediatek/mt6990/base-files/`), which calls
`/lib/air6/upgrade.sh` from the `air6-tools` package. On boards other than `softbank,air6`, `platform.sh` refuses.

## The package

`./build.sh` makes `out/$STAMP/sysupgrade.bin` after signing (`build/finish.sh`, `build/make_sysupgrade.py`). It is
an uncompressed tar followed by fwtool metadata.

Tar members, exactly these, in this order:

| Member | Content |
| --- | --- |
| `sysupgrade-softbank_air6/` | Directory |
| `sysupgrade-softbank_air6/CONTROL` | `key=value` lines (below) |
| `sysupgrade-softbank_air6/kernel` | `boot.img` of the build, 32 MiB (Android boot image with the MTK signature) |
| `sysupgrade-softbank_air6/root` | The squashfs of `rootfs.img`, cut to its `bytes_used` rounded up to 4 KiB |

`CONTROL` has exactly these keys, in this order. The unit parses it and never sources it.

| Key | Value |
| --- | --- |
| `BOARD` | `softbank_air6` |
| `format` | `air6-sysupgrade/1` |
| `kernel_size`, `kernel_sha256` | Size and sha256 of `kernel` |
| `root_size`, `root_sha256` | Size and sha256 of `root` |
| `squashfs_bytes_used` | `bytes_used` from the squashfs superblock |
| `trial` | `1` for a trial image, `0` for a normal image |
| `modem_version` | `V.._.._P..` for a build with the modem, empty without |
| `fork` | Fork commit (40 hex digits) |
| `kit` | Kit commit, or `none` when the kit inputs were not exactly that commit (changed before or during the build) |

Metadata: `supported_devices` = `softbank,air6`, `compat_version` = `1.0`. The boot image's own MTK signature,
checked by the bootloader at boot, is the only signature; the package has none of its own.

The kit checks the package after the build (`scripts/check_sysupgrade.py`, the `sysupgrade.bin` lines in
`CHECK.txt`): the fwtool trailer read back by the build tree's `fwtool`, the metadata, the members, every `CONTROL`
value, `kernel` = `boot.img`, `root` = the start of `rootfs.img` with only zeros after it, `trial` against the boot
image's policy and `modem_version` against the build. See [build.md](../build.md#what-a-build-leaves-behind).

## Checks before anything is written

The unit runs these checks in `platform_check_image`. `sysupgrade -T` runs only them (`./device.sh upgrade` does
that first), and `sysupgrade`, LuCI and procd run them before an update. They change nothing on the unit.

1. **Package:** the metadata as above; the members and their order; every `CONTROL` key and value; the member sizes
   equal to `CONTROL`; the sha256 of `kernel` and `root`; `kernel` starts with `ANDROID!` and is 32 MiB; `root`
   starts with `hsqs`, its `bytes_used` equals `CONTROL` and its size is `bytes_used` rounded up to 4 KiB; the
   squashfs leaves at least 16 MiB of `rootfs_X` for the settings area.
2. **State of the unit:** the boot control record is valid; the next boot slot is the running slot; the running
   slot is marked good (`success=01`); the root file system is `rootfs_` of the running slot; no backup, restore or
   other update of the other slot is in progress (the update reservation `/tmp/air6-update`).
3. **What the other slot holds:**
   - The stock firmware (its rootfs has `/lib/upgrade/bootctrl.sh`): `air6-stock verify` must pass, that is a
     confirmed stock backup of that slot that still matches it ([stock-backup.md](stock-backup.md#the-sysupgrade-gate)).
   - OpenWrt for the Air 6 (`/usr/sbin/air6-slot` or `air6-abguard`): no further check.
   - No squashfs, and the slot is not marked good (a write that did not finish): no further check.
   - Anything else, or the check itself fails (cannot read, cannot mount): refused.
4. **Modem:** when `modem_version` is set, it must equal the version in the other slot's `md1img`
   ([features/modem.md](../features/modem.md#updating-with-the-modem)).

Every refusal of these checks prints the reason and returns 74.

## The write

After the check, OpenWrt's sysupgrade stops the services and calls two hooks. Both ignore INT, TERM, HUP and PIPE,
so a signal cannot end a run between a boot control write and the check of its result.

**Admission** (`platform_pre_upgrade`, before the switch to the RAM file system):

1. Refuse `-s`; check that `/tmp` has room for two copies of the package, the settings and 16 MiB.
2. Take the update reservation `/tmp/air6-update` (phase `sysupgrade`). While it exists, `air6-slot set-active`,
   `air6-stock backup` and `air6-stock restore` are refused.
3. Copy the package and the settings archive into a private run directory and run all checks again on the copies,
   with the state and the stock check under the reservation (the stock check reads 13 partitions again; about 10 s
   on unit 1).
4. Write a context file with the run's values. The write step uses only the copies and this file.

A failure here cannot stop OpenWrt's sysupgrade, which has already stopped the services and continues anyway. The run
is then marked "not admitted", the reservation is removed, the write step writes nothing, and the unit reboots into
the unchanged running slot.

**Write** (`platform_do_upgrade`, in the RAM file system):

1. Check the run context and the hashes of the copies.
2. Mark the other slot not good (`success=00`), read the record back. From here the slot cannot be selected by
   `set-active` or the LEVEL key until the run activates it.
3. Write `kernel` to `boot_X` and `root` to `rootfs_X` (only their lengths).
4. Write the settings area ([Settings](#settings)).
5. `sync`, drop the page cache, read back and compare the sha256 of everything written.
6. Activate the other slot for the next boot as a new slot after a write
   ([boot-control.md](boot-control.md#who-writes-the-bytes)); the running slot keeps its success flag. Read the record
   back.
7. Remove the reservation.

`platform_copy_config` does nothing on the Air 6: the settings were written in step 4, before the activation. On unit
1 the write step took about 12 s.

## Settings

The settings are what OpenWrt's sysupgrade keeps (`sysupgrade -l` lists the files). The Air 6 writes them into the
new slot itself:

- The settings area starts at `squashfs_bytes_used` rounded up to 64 KiB inside `rootfs_X`, where OpenWrt's fstools
  look for the overlay.
- With settings: the first 4 KiB there are zeroed, then the settings archive is written and read back. On the first
  boot of the new slot, fstools restores it. The archive must be a complete `tar.gz` starting with `1f 8b 08 00`
  and must fit behind the squashfs; otherwise the run is refused.
- Without settings (`-n`, `./device.sh upgrade ... --no-config`): 4 KiB are zeroed there and read back. The new slot
  starts with the defaults built into its image (files from `local/files` in the image still apply). Not tried on a
  unit.
- Either way, the overlay of the build that the slot held before is not mounted.

`user_data`, the stock firmware's data partition, is never written ([partitions.md](partitions.md)).

The files in `/etc/air6-slot/` (the stock backup marker, `failed-events`, `last-upgrade`) are not on OpenWrt's default
list of kept files: the new slot does not get the old slot's files. For the stock backup marker this was seen on unit
1 (2026-10-31). The new slot records its own `last-upgrade` from the pstore at its first start-up
([below](#the-result-record)).

## How a run ends

OpenWrt's `upgraded` process reboots as soon as the write step ends, whatever its result. The write step therefore
ends in one of four states:

| State | When | What happens |
| --- | --- | --- |
| `refused` | Not admitted, or stopped before any write; the record reads back with the running slot next and marked good | Reboot into the running slot |
| `failed` | Marking the other slot not good (step 2 of the write), a partition or settings write, a read-back or the activation failed; the record reads back with the running slot next and marked good | Reboot into the running slot. The other slot may have been marked not good and may be partly written; the `phase=inv` line of the record shows whether it was marked not good (`read-back=` equal to `requested=`) |
| `written` | Everything written, read back and activated | Reboot into the new slot |
| `halted` | The boot control record is not certain: unreadable, invalid, a write whose result is unknown, or another slot than the running one is next | No reboot (below) |

**Halted:** the write step does not end, so `upgraded` keeps the watchdog fed and nothing reboots. The power LED
blinks red. The serial console shows the phase, the last record read, the command that prints the 10 bytes, and a
shell; `reboot -f` boots whatever the record says. The services were stopped before the write, so there is no network.
A power cycle has the same effect as `reboot -f` (a power cycle out of this state has not been tried). There is no
automatic rollback of the record. What to do:
[troubleshooting.md](../troubleshooting.md#sysupgrade-stopped).

## The first boot of the new slot

The new slot starts like any slot after a write: not marked good, with its retry count preset to 02
([how the bootloader uses it](boot-control.md#how-the-bootloader-uses-them)).

- When start-up finishes, a normal image marks the slot good; a trial image waits for `trial-commit` and returns by
  its timer otherwise. The policy belongs to the image (its kernel command line), not to the settings.
- When it never finishes and the unit resets, the bootloader returns to the previous slot after a few attempts
  ([boot-control.md](boot-control.md#how-the-bootloader-uses-them)); that slot then records the failed start under
  "failed updates".

Details: [boot-control.md](boot-control.md).

## The result record

Each step of a run is written as one line (`air6-upgrade/1 token=... phase=...`) to the console and to the pstore
message buffer `/dev/pmsg0` (64 KiB, set by `ramoops.pmsg_size` in the kernel command line). The last line has
`end=1`, the state (`refused`, `failed`, `written`, `halted`), the phase and the last boot control record read; for a
run that did not halt, also the two slots and the image digest.

At the next start-up, `air6-slot boot-done` copies the latest run from `/sys/fs/pstore/pmsg-ramoops-0` to
`/etc/air6-slot/last-upgrade` in the slot that started, and `air6-slot status` shows it as "last sysupgrade record".

- A power cut before that start-up (a cold boot) loses the record.
- The record stays in the slot that started first after the run. When the new slot started and the unit then went
  back (trial timer, switch, failed starts), the old slot has no record.
- A run without a begin or an end line is kept as incomplete: "result unknown".
- Whether the record survives several warm reboots before it is copied has not been tried.
- The record says whether the write finished, not whether the new slot started.

## What `device.sh` does

`./device.sh upgrade DEVICE STAMP [--no-config]`, from the kit computer:

1. Checks that `out/$STAMP/CHECK.txt` ends in `RESULT: PASS`, that the unit runs OpenWrt with
   `/lib/air6/upgrade.sh`, and that `sysupgrade.bin` exists.
2. Uploads `sysupgrade.bin` to a new private file `/tmp/air6-sysupgrade.XXXXXX` and compares its sha256.
3. Runs `sysupgrade -T` on that file. On a refusal it removes the upload and stops: nothing was written.
4. Records the request in `out/$STAMP/upgrade-request-<time>`: unit, boot ID, slot it came from, image sha256,
   settings kept or not.
5. Starts `sysupgrade` on the unit in the background and returns.

`./device.sh upgrade-check DEVICE STAMP`, after the unit is back, compares the newest request with the unit:

- the record's begin line has the request's boot ID, and its end line the request's image;
- the slot that runs now against the slot the request came from;
- the root file system against `rootfs_` of the slot that runs.

When no record of the request is on the running slot, it prints UNKNOWN and what the boot control record shows now.
Its messages and what to do: [3-update.md](../3-update.md#check-the-result) and
[troubleshooting.md](../troubleshooting.md#upgrade-check-does-not-say-written).

LuCI's "Flash new firmware image" and a manual `sysupgrade` run the same checks on the unit. `upgrade-check` works only
with the request that `./device.sh upgrade` records; after another update, the "last sysupgrade record" in
`air6-slot status` shows the result. A LuCI update was tried once (2026-11-01, slot A to slot B, settings kept); a
manual `sysupgrade` has not been tried ([status.md](status.md)).

## Limits

- Not safe against a power cut. Between steps 2 and 6 of the write the record keeps the running slot next and the
  other slot not good, so by the code a cut there boots the running slot; a cut during a write of the record itself
  has an unknown result. No power cut during an update has been tried.
- The admission takes the reservation after the services were stopped. A stock restore started between the check and
  the admission is detected and the update writes nothing, but the restore itself may have been ended by the service
  stop.
- What has been tried on a unit: [status.md](status.md).
