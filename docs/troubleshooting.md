# Troubleshooting

This page is for when a command or a start-up does not end the way the stage pages describe. Find the symptom in the
headings below; each section says what has changed on the unit, what to do next, and when to stop.

- [The build fails](#the-build-fails)
- [The install stops](#the-install-stops)
- [OpenWrt starts but you cannot reach it](recovery.md) (moved to its own page)
- [sysupgrade stopped](#sysupgrade-stopped)
- [upgrade-check does not say written](#upgrade-check-does-not-say-written)
- [The stock restore stops](#the-stock-restore-stops)
- [set-active or switch stops](#set-active-or-switch-stops)

In the commands, `root@DEVICE` is the unit while it runs the stock firmware (its address on your network), and
`root@192.168.1.1` is the unit while it runs OpenWrt, reached from the kit computer on jack 1. `$STAMP` is the build
ID, the name of a directory under `out/`.

## The build fails

`./build.sh status $STAMP` ends with `result: failed` or `result: stopped without DONE or FAILED`.

- Run `./build.sh logs $STAMP` and read the log files in `out/logs-$STAMP/`. The last step in `progress.log` names
  the step that failed; its log file has a matching name (for example `build.log` or `finish.log`).
- If that step is `finish: pack, sign, check`, the image check may have failed:
  `grep ^FAIL out/logs-$STAMP/finish.log` lists the failed checks. A build that failed its check is never copied to
  `out/$STAMP/` (`collect` says it is not done), and `install` and `upgrade` refuse it.

The build commands: [Build steps and failures](build.md#build-steps-and-failures). What each file of a build is and
what the image check covers: [What a build leaves behind](build.md#what-a-build-leaves-behind).

## The install stops

`./device.sh install root@DEVICE $STAMP` did not end with `installed; next: ./device.sh reboot root@DEVICE`.
**Do not reboot.** Find the case below that matches the output first.

### Refused before the upload

These messages come from the kit computer before anything is sent; nothing on the unit changed.

- `out/$STAMP/CHECK.txt not found` or `out/$STAMP did not pass the image check`: a wrong build ID, or a build that
  failed its image check ([The build fails](#the-build-fails)).
- `root@DEVICE is not running the stock firmware`: `install` works only from the stock firmware. A unit that already
  runs OpenWrt is updated with [Keep](2-keep.md) while the other slot holds the stock firmware, otherwise with
  [Update](3-update.md); an image without sysupgrade support first goes back to the stock firmware
  ([docs/4-going-back.md](4-going-back.md#units-with-an-image-from-an-earlier-kit)).
- `the image's modem programs are ... but the modem firmware in the target slot is ...`, then `refusing to install`:
  the build carries modem programs for another slot. Copy the programs of the slot the install writes and build again
  ([docs/features/modem.md](features/modem.md#1-copy-the-modem-programs)).

### `abort: ...`

A check on the unit failed before the OpenWrt slot or the boot control bytes were written: for example the unit does
not run the stock firmware, an upload is incomplete (`abort: boot image hash`), or the boot control bytes are not as
expected (`abort: unexpected bootctrl ...`). The slots and the boot control bytes are unchanged; only the uploaded
files in `/tmp` on the unit were written. Fix the cause the message names, then run the install again.

### `WRITE VERIFY FAILED`

The data read back from the OpenWrt slot does not match the image. The boot control bytes were not changed, so the
unit keeps booting the stock firmware. Run the install again.

### `UNEXPECTED bootctrl`

The slot was written, but the boot control bytes did not end up as expected. **Do not reboot.**

1. Find the line in the output that starts with `rollback (run on the unit before rebooting):`.
2. Log in to the unit (`ssh root@DEVICE`) and run the command after the colon. It writes back the bytes from before
   the install.
3. Run `./device.sh status root@DEVICE`. The `bootctrl=` value must equal the `bootctrl before=` line of the install
   output. Only then is a reboot safe; otherwise keep the output and do not reboot.

### Any other ending

The connection dropped, ssh printed an error, or there is no `installed;` line at the end: do not reboot. Keep the
output and run `./device.sh status root@DEVICE`.

- No `bootctrl before=` line in the output: nothing but the uploaded files in `/tmp` changed. Run the install again.
- The `bootctrl=` value equals the `bootctrl before=` line: nothing selects the new slot. Run the install again.
- It changed: both partitions were written and verified before that (the install changes the bytes only afterwards),
  but the change of the bytes may be incomplete. If they read as after a normal install (the booted slot priority
  `0e` and success `01`; the new slot priority `0f`, retry `02`, success `00`: `0e000101000f02000100` from slot A,
  `0f020001000e00010100` from slot B; see [boot control](reference/boot-control.md#the-boot-control-bytes)), the
  install finished: continue with [step 4 of docs/1-try.md](1-try.md#4-reboot-and-connect). Otherwise use the
  `rollback` line as in [`UNEXPECTED bootctrl`](#unexpected-bootctrl); if it was not printed, do not reboot and keep
  the output.

## OpenWrt starts but you cannot reach it

The ways out when OpenWrt does not answer at 192.168.1.1 (the connection, waiting for a trial image, failsafe mode,
the LEVEL key) are in [docs/recovery.md](recovery.md).

## sysupgrade stopped

An update with `./device.sh upgrade` can stop in four ways:

- `./device.sh upgrade` itself ends with an error, for example "the unit refused the package (see above); nothing
  was written". Nothing was written and the unit did not reboot. See
  [When the unit refuses](3-update.md#when-the-unit-refuses).
- The unit reboots, and `./device.sh upgrade-check` says `refused` or `failed`. See
  [`result: refused` or `result: failed`](#result-refused-or-result-failed).
- The unit does not come back and the power LED blinks red. See below.
- The unit does not come back and the power LED does not blink red. Wait 5 minutes (a new slot that does not start
  gets a few attempts before the bootloader returns to the old one;
  [details](reference/boot-control.md#how-the-bootloader-uses-them)). If the unit then answers at 192.168.1.1, run
  `upgrade-check` ([upgrade-check does not say written](#upgrade-check-does-not-say-written)). If it does not, see
  [When you cannot reach the unit](recovery.md).

### The power LED blinks red

sysupgrade could not be sure which slot boots next (the boot control bytes did not read back as expected or could not
be read), so it stopped instead of rebooting. The network is down in this state.

- With a serial console: the console shows `air6-upgrade: STOPPED in phase ...` with the last bytes read, the command
  that prints the 10 boot control bytes, and a shell. Read the bytes as in
  [docs/reference/boot-control.md](reference/boot-control.md); `reboot -f` boots whatever they say, as a power cycle
  would.
- Without a serial console: unplug the power and plug it in again. The unit then boots whatever the boot control
  bytes say, which is what an automatic reboot would have done. Allow up to 5 minutes (a new slot that does not start
  gets a few attempts before the bootloader returns to the old one), then run
  `./device.sh status root@192.168.1.1`. `upgrade-check` will say UNKNOWN, because a power cycle loses the record.
  Run `upgrade` again only when the status shows the booted slot as next and `success=01`. If the unit does not
  come back at all, only the serial console can show why.

When the update was writing the stock firmware's slot ([stage 2, Keep](2-keep.md)), the stopped run may have
changed or partly overwritten that slot: do not assume it is still usable, and keep the backup. The stock firmware
then comes back only from the backup
([docs/4-going-back.md](4-going-back.md#restore-the-stock-firmware-from-the-backup)).

Tried on one unit: only an imitation of this stop by a test script, left with `reboot -f` over the serial console.
The stop code as built into the image, and a power cycle out of it, have not been tried.

## upgrade-check does not say written

After an update, `./device.sh upgrade-check root@192.168.1.1 $STAMP` prints the status and then a line starting with
`result:`. The expected one is `result: written, and the unit runs the new slot X on rootfs_X`
([Check the result](3-update.md#check-the-result)). This section covers the others.

If `upgrade-check` cannot connect yet, wait and run it again. If it says `no upgrade request recorded for out/$STAMP`,
the build ID is not the one passed to `./device.sh upgrade`; `upgrade-check` can only judge an update started with
`./device.sh upgrade`. For an update from LuCI, read the status instead
([From LuCI instead](3-update.md#from-luci-instead)).

### `result: refused` or `result: failed`

Nothing was activated: the old slot is still the next boot slot, and a partly written new slot stays marked not good
(neither `set-active` nor the LEVEL key selects it).

- "refused": nothing was written.
- "failed": a write was started (or may have been) and the run did not finish.

The status shows the end line of the record (`state=`, `phase=`, `last=`). `upgrade-check` prints the whole record of
the request above its result line, including the lines with `msg=error` that name the step that failed (spaces appear
as `_`). A reason that is not among them was printed only on the unit's console during the update. The record is also
in a file on the unit:

    ssh root@192.168.1.1 cat /etc/air6-slot/last-upgrade

Fix the cause and run `upgrade` again. When the update was writing the stock firmware's slot (stage 2, Keep), after
"failed" that slot may have changed or been partly overwritten: do not assume it is still usable, keep the backup,
and check the phase and the read-back values in the record before retrying. If the `phase=inv` line shows
`read-back=` equal to `requested=`, the slot is marked not good and cannot be selected. The stock firmware then comes
back only from the backup ([docs/4-going-back.md](4-going-back.md#restore-the-stock-firmware-from-the-backup)).

### `result: written (the write finished), but the unit runs the old slot X again`

The unit is back on the old slot after a finished write; what it means and what to do: the
[result table](3-update.md#check-the-result).

### `result: UNKNOWN - the unit has no record of this request`

The result of this request is not known: the running slot has no record of it (a power cut, for example, loses the
record). In the two return tests on the unit it was UNKNOWN both times. `upgrade-check` then adds what the status
shows. These lines describe the slots now, not the result of the request:

| Line after UNKNOWN | What it shows | Next |
| --- | --- | --- |
| "listed under 'failed updates'" | The other slot reached the bootloader's retry limit before it was marked good. An uncommitted trial image that was rebooted twice gives the same entry, and the entry may be from an earlier attempt | Decide from what you did; `upgrade` again if you want the build |
| "not marked good, retry .." | The other slot was selected for a boot after the write and is not marked good; whether it started, and where its record is, are not known | If you know a trial timer returned the unit: `upgrade` again and keep it in time |
| "whether it was started is unknown" | No evidence either way | Check `status`; `upgrade` again only if the booted slot is next and `success=01` |
| "runs slot X, not the slot the request came from" | The unit runs the other slot; which image it runs is not confirmed | Check `root=rootfs_X`, `policy=`, `timer=` and that it works; with a trial image, `trial-commit` after the checks |
| (no further line) | The unit runs the slot the request came from, and the other slot is marked good | Check `status`; `upgrade` again only if the booted slot is next and `success=01` |

### Any other result

- `result: MISMATCH - the record's image ... is not the requested one`
- `result: written, the unit booted slot X, but its root file system is not rootfs_X`
- `result: UNKNOWN - the record of this request is incomplete (state '...')` (state `halted`: see
  [sysupgrade stopped](#sysupgrade-stopped))

These are not expected states. Do not run `upgrade` again; keep the output and check `status`. With the root file
system message, the status shows a `WARNING:` line instead of `root=rootfs_X`, and the slot is not marked good.

## The stock restore stops

`./device.sh restore-stock root@192.168.1.1 FILE` did not end with `next: ./device.sh reboot root@192.168.1.1`.
Do not reboot until you have read the case that matches the output.

### Refused before the restore started

The slot was not touched in these cases.

- `FILE failed the checks; nothing sent to the unit`: the file is not a complete backup from `stock-backup`; the line
  above it says which check failed.
- `FILE is a backup of slot X, the booted slot; boot the other slot first`: restore from OpenWrt running in the other
  slot than the backup's ([Start the other slot](4-going-back.md#start-the-other-slot)).
- `this image has no /usr/sbin/air6-stock`: the running image is too old for this command.
- `air6-stock stage failed` or `uploading ... failed`: run `restore-stock` again.

### The exit code

`./device.sh restore-stock` exits with the restore's exit code (also shown as `rc N`):

- 3, 4 or 5 (`restore not done`): refused, busy or a read error. Nothing was written. The `error:` line above it gives
  the reason, for example:
  - `slot X differs from the backup in partitions that are never written`: the 11 partitions the restore never
    writes (modem and bootloader firmware among them) are not the ones in the backup, so the restore refuses it.
  - `the backup is from another unit`.
  - `the booted slot X is not marked successful`: with a trial image, run `./device.sh trial-commit root@192.168.1.1`
    first.
  - `an update of the other slot is in progress` or `stale update reservation`: see
    [After an interrupted backup or restore](#after-an-interrupted-backup-or-restore).
- 6 (`restore stopped after a change was started`): a write was started, but the restore did not end normally.
  Do not rerun it straight away. Read the `outcome:` lines (also shown by
  `ssh root@192.168.1.1 air6-stock result DIR`, unless the output says the result could not be saved) and run
  `./device.sh status root@192.168.1.1`:
  - `slot X stays unsuccessful (not selectable)`: the slot may be partly written, but neither `set-active` nor the
    LEVEL key selects it. Run `restore-stock` again with the same file.
  - `the boot control record is unchanged`: which slot boots next did not change, and slot X is not selected.
    Either no partition was written (`no partition of slot X was written`), or slot X was already not marked good
    from an earlier run and stays so. Run `restore-stock` again.
  - `slot X was activated`: the slot was restored and boots next; only the end failed (for example the result could
    not be saved, or the update reservation remains, which keeps `set-active` refused until a reboot). Reboot with
    `./device.sh reboot root@192.168.1.1` as after a restore that worked.
  - `the next boot slot is uncertain` or `slot X is marked successful in the last record read`: do not reboot before
    the status shows which slot boots next and whether it is marked good.
  - No `outcome:` line about slot X: nothing was written. If `this run's update reservation remains` is shown, reboot
    before running `restore-stock` again; otherwise run it again.

### The SSH connection dropped

If the connection drops during the restore, the kit asks the unit for the outcome itself and continues as above.
When it cannot, it prints `the outcome is not known yet` and the command to ask later,
`ssh root@192.168.1.1 air6-stock result DIR` (with the directory it printed). Run that command before anything else
on that slot:

- `state=done` and `rc=0`: the restore worked; reboot with `./device.sh reboot root@192.168.1.1`.
- `state=failed` or `state=refused`: read its `rc=` and `outcome:` lines as in [The exit code](#the-exit-code).
- `no result in DIR: no restore was started with this run directory`: nothing was written; run `restore-stock`
  again.
- `the restore is still running`: wait and ask again.
- `the restore run ended without a final result`: the outcome is unknown. Check `./device.sh status
  root@192.168.1.1` and do not reboot before it shows which slot boots next and whether it is marked good.

### After an interrupted backup or restore

While a backup or a restore runs, `set-active` and `upgrade` are refused ("an update of the other slot is in
progress"). If one was interrupted, `set-active`, `upgrade`, `stock-backup` and `restore-stock` stay refused until
the next reboot. How a restore works: [docs/reference/stock-backup.md](reference/stock-backup.md).

## set-active or switch stops

`./device.sh set-active` (or `air6-slot set-active`) did not print `slot X boots next (...)`, or `./device.sh switch`
did not end with `slot X preferred, retry preset 02` and `next: ./device.sh reboot root@DEVICE`
([Going back](4-going-back.md#start-the-other-slot)). **Do not reboot** until the status shows which slot boots next.

### `set-active`

- An `error:` line saying `not selecting it`, `nothing changed` or `boot control is busy`, or a message that the unit
  is not running OpenWrt: nothing was written. Fix the cause it names and run `set-active` again.
- `error: set-active: write of ... failed`, a dropped connection, or any other ending: the write may have been
  started. Run `./device.sh status root@192.168.1.1` (from another computer: `ssh root@192.168.1.1 air6-slot
  status`):
  - `next=` names the slot you selected and its line shows `success=01`: the selection took effect; reboot as in
    [Start the other slot](4-going-back.md#start-the-other-slot).
  - `next=` names the booted slot: nothing selects the other slot. Run `set-active` again.
  - `next=unknown`, `warning: unexpected boot control record`, or no status: do not reboot. Keep the output; how to
    read the record: [boot control](reference/boot-control.md#reading-the-status).

### `switch`

`switch` writes the same boot control bytes as an install, without writing the slot.

- `abort: ...`: a check failed before anything was changed.
- `UNEXPECTED bootctrl`: do not reboot. Undo it with the `rollback` line as in
  [`UNEXPECTED bootctrl`](#unexpected-bootctrl) of the install.
- A dropped connection, or no `slot X preferred` line: run `./device.sh status root@DEVICE`. If `bootctrl=` equals the
  `bootctrl before=` line of the output (or there is no such line), nothing changed: run `switch` again. If it reads
  as after an install (see [Any other ending](#any-other-ending) of the install), the switch finished: reboot.
  Otherwise use the `rollback` line; if it was not printed, do not reboot and keep the output.
