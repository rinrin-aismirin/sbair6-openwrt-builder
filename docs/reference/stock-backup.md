# Stock backup and restore

This page specifies the backup of a stock firmware slot and its restore: what is saved, how the backup is checked
and confirmed, the check that guards sysupgrade, and the steps of a restore. The steps to run are in
[2-keep.md](../2-keep.md#1-back-up-the-stock-slot) and
[4-going-back.md](../4-going-back.md#restore-the-stock-firmware-from-the-backup); the partitions are listed in
[partitions.md](partitions.md).

## Why it exists

No stock firmware image is published. Once OpenWrt overwrites the slot that held the stock firmware (the first
`./device.sh upgrade` does), the only way to get the stock firmware back is a backup of that slot taken from the same
unit before. The backup and the restore both run from OpenWrt, in the other slot than the one backed up.

## What is saved

A backup holds the 15 partitions of one slot. The restore writes 4 of them and requires the other 11 to be
unchanged:

| Group | Partitions | Backup | sysupgrade gate | Restore |
| --- | --- | --- | --- | --- |
| fixed | `connsys_gnss`, `md1img`, `md1dsp`, `spmfw`, `pi_img`, `dpm`, `medmcu`, `sspm`, `mcupm`, `lk`, `tee` | saved | must match | must match; never written |
| restored | `mcf1`, `mcf2`, `boot`, `rootfs` | saved | `mcf1` and `mcf2` must match | written from the backup |

OpenWrt never writes the fixed group of any slot, so a slot that OpenWrt overwrote still holds the stock firmware's
fixed partitions. The shared partitions (NV, `user_data` and the others) are not part of the backup and are not
written by the restore.

## Commands

On the kit computer (`device.sh`, needs OpenWrt with `/usr/sbin/air6-stock` on the unit):

    ./device.sh stock-backup DEVICE [SLOT]     # SLOT: default the other slot
    ./device.sh restore-stock DEVICE FILE      # the slot comes from FILE

On the unit (`/usr/sbin/air6-stock`, package `air6-tools`):

| Command | Role |
| --- | --- |
| `backup SLOT -` | Read the 15 partitions of SLOT, stream the archive to stdout, write a pending marker |
| `confirm SLOT BACKUP_ID DIGEST` | Make the pending marker of SLOT the valid one, if all three match exactly |
| `verify SLOT` | Check that SLOT still matches its confirmed backup (the [sysupgrade gate](#the-sysupgrade-gate)) |
| `stage` | Create a private run directory for a restore and print its path |
| `restore SLOT DIR` | Restore SLOT from the files in DIR; never reboots |
| `result DIR` | Print the outcome of the restore run in DIR |

Exit codes: 0 done, 2 usage, 3 refused (nothing changed), 4 busy (nothing changed), 5 environment or read error
(nothing changed), 6 a change was started and the run did not complete, or its result is uncertain. `result` exits 0
for a finished run (the run's own code is in its output), 3 when DIR has no result, 4 while the run is still going,
5 when the run ended without a final result.

## The archive

`device.sh stock-backup` saves the archive as `out/stock/air6-stock-<slot>-<time>-<id8>.tar` on the kit computer:
directory `out/stock/` mode 0700, file mode 0600. It holds 282 MiB of partition data; the file for slot A of unit 1
was 295,710,720 bytes. It contains data specific to the unit.

Members, exactly these, in this order, regular files only, uncompressed:

1. `META`
2. `SHA256SUMS`
3. The 15 images `<partition>_<slot>.img`, fixed group first, then `mcf1`, `mcf2`, `boot`, `rootfs`.

`META` has fixed `key=value` lines, parsed and never sourced:

| Key | Value |
| --- | --- |
| `format` | `air6-stock-backup/1` |
| `backup_id` | 32 random hex digits |
| `slot` | `a` or `b` |
| `unit` | The [unit identity](#unit-identity) |
| `created` | UTC time from the unit's clock (may be wrong) |
| `stock_version` | Stock firmware version from the slot's rootfs, or `unknown` |
| `md1img_version` | Modem firmware version from the slot's `md1img`, or `unknown` |
| `size_<partition>_<slot>` | Size in bytes, one line per partition |

`SHA256SUMS` lists the sha256 of `META` and of the 15 images, in archive order. The backup's digest is the sha256 of
`SHA256SUMS`; it binds the slot, the unit and the content.

## Unit identity

The unit identity is the ext4 UUIDs of the shared partitions `nvcfg`, `nvdata`, `protect1` and `protect2`. It
identifies these file systems, not the hardware. An unreadable, empty or all-zero UUID is an error. A unit whose NV
file systems were reformatted or replaced no longer matches its own backups, and the restore refuses it; there is no
override.

## Taking a backup

`air6-stock backup SLOT -` on the unit:

1. Refuses the running slot, and a slot whose rootfs does not hold the stock firmware (no
   `/lib/upgrade/bootctrl.sh`) or cannot be mounted read-only to check that.
2. Refuses while `mcf1`, `mcf2`, `boot` or `rootfs` of SLOT is mounted, while the modem/NV lock
   (`/var/lock/air6-modem.lock`) is held, and while another backup, restore or update holds the update reservation
   `/tmp/air6-update`. It holds both itself until it ends.
3. Needs free space in `/tmp` for the 15 images plus 16 MiB: it reads each partition once into a private directory
   there, hashes those files and streams the archive of the same files.
4. After the archive was sent, writes the pending marker. A failed backup never touches the valid marker.

`device.sh stock-backup` receives the archive into a private temporary file and checks it before keeping it: a
complete tar, exactly the members above in order, regular files, `SHA256SUMS` well-formed and matching, `META`
well-formed and for the requested slot, each image the size `META` gives. It then saves the file under its final
name (never replacing an existing file), reads it back, and only then runs `air6-stock confirm`. When the confirm
fails, the file is kept and the command prints the `confirm` line to run again; repeating it is safe.

On unit 1 a backup took 57 s (2026-10-30).

## The marker

The marker is the unit's record that a backup was checked and saved:

- `/etc/air6-slot/stock-backup-<slot>`: the valid marker. `/etc/air6-slot/stock-backup-<slot>.pending`: a candidate.
- Mode 0600, in the overlay of the slot OpenWrt runs from.
- Content: the `META` lines, `digest=`, the `SHA256SUMS` lines.
- A new backup replaces only the candidate; `confirm` turns the candidate into the valid marker when slot, backup ID
  and digest match exactly.

A valid marker means "the kit checked and saved this backup at confirm time". It does not prove that the file still
exists. It is used only by the [sysupgrade gate](#the-sysupgrade-gate); the restore checks the archive itself.

The marker is not carried over by sysupgrade ([sysupgrade.md](sysupgrade.md#settings)): after an update, the slot
that runs has no marker until a new backup is taken.

## The sysupgrade gate

sysupgrade refuses to overwrite a slot that holds the stock firmware unless `air6-stock verify SLOT` passes
([sysupgrade.md](sysupgrade.md#checks-before-anything-is-written)). `verify` requires:

- a valid marker for SLOT, from this unit;
- the 15 partition sizes as in the marker;
- SLOT still holds the stock firmware;
- the 11 fixed partitions and `mcf1`, `mcf2` match the marker's hashes (13 partitions; about 10 s on unit 1).

`boot` and `rootfs` are not compared: the stock firmware's rootfs changes while it runs.

The result is valid when it is taken; it does not reserve the slot. sysupgrade runs it once in the check and again
under its reservation.

The stock firmware changes `mcf1` and `mcf2` of its slot when it runs, so after a boot of the stock firmware
`verify` fails against an older backup (seen on unit 1, 2026-10-30). A new backup is then needed.

## Restoring

`device.sh restore-stock DEVICE FILE` checks the archive on the kit computer as for a backup, reads the slot from it,
refuses when that slot is the running slot, runs `air6-stock stage`, uploads `META`, `SHA256SUMS` and the 4 restored
images into the run directory, and runs `air6-stock restore`. When the SSH connection drops during the restore, it
asks `air6-stock result DIR` for the outcome.

`air6-stock restore SLOT DIR` on the unit:

1. **Input** (no change): DIR is an unused run directory from `stage` holding only the expected files; `META` and
   `SHA256SUMS` are well-formed and for SLOT; `unit` equals this unit; the sizes match `META` and the partitions; the
   4 images match their hashes; `/tmp` has at least 4 MiB free.
2. **Target** (no change): SLOT is not the running slot; the modem/NV lock is free (held from here to the end); no
   file system left detached by a modem stop; the 4 restored partitions are not mounted; the 11 fixed partitions
   match the backup.
3. **Admission**: under the boot control lock, the record must be valid, the running slot next and marked good, and
   no update reservation may exist. The run then takes the reservation and marks SLOT not good (`success=00`), read
   back. From here a failure is exit 6.
4. **Write** `mcf1`, `mcf2`, `boot`, `rootfs` of SLOT; `sync`; drop the page cache; read back and compare the
   sha256 of all four.
5. **Activate**, under the boot control lock and only if the record is still what step 3 left: SLOT boots next as a
   new slot after a write ([boot-control.md](boot-control.md#who-writes-the-bytes)). Read back.
6. Remove the reservation, write the result to `DIR/result`, delete the uploaded images.

A run directory is used once; a new attempt needs a new `stage` and upload. INT and TERM that arrive during a boot
control write are handled after its result is known.

On unit 1 a restore took 63 s (2026-10-30).

**After a restore**, the next boot starts the restored stock firmware with its retry count preset to 02; if it does
not start, the bootloader returns to the OpenWrt slot after a few attempts
([boot-control.md](boot-control.md#how-the-bootloader-uses-them); a failed start after a restore has not been
tried). The stock firmware marks its slot good itself at the end of its start-up. It
comes back with the settings its rootfs had when the backup was taken, and finds its own `/data`, which OpenWrt never
writes. OpenWrt stays in its slot.

## When a restore stops

A run that ends with exit 6 prints `outcome:` lines built only from what it read back:

- which partitions of SLOT were written, and whether all four were read back as the backup;
- whether SLOT was activated; otherwise whether SLOT stays not good, the record is unchanged, or the next boot slot is
  uncertain;
- whether an update reservation was left behind.

There is no automatic rollback of the record and no reboot. A reservation left behind is never taken over and has no
command to remove it: it ends with the next reboot, and until then `set-active`, backups, restores and updates are
refused. The end of the reservation says nothing about the slot. Whether the slot is selectable after a reboot
follows from the record:

- Not activated and read back with SLOT `success=00` (`stays unsuccessful`, or `unchanged` with success 00): neither
  `set-active` nor the LEVEL key selects it.
- `unchanged` with success 01: no partition was written; the slot is as it was before the run.
- `activated`: SLOT boots next, as after a restore that worked.
- `uncertain`, or SLOT marked successful in the last record read: not known; the status has to show which slot boots
  next and whether it is marked good before a reboot.

What to do: [troubleshooting.md](../troubleshooting.md#the-stock-restore-stops).

## Limits

- Not safe against a power cut.
- The restore does not write the fixed partitions. If they no longer match the backup (for example after a stock
  firmware update cloned other ones over them; read from the stock update script, not observed), the restore
  refuses, and the kit has no tool that writes them.
- What has been tried on a unit: [status.md](status.md).
