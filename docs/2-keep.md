# Keeping OpenWrt

This page is stage 2: once you have decided to use OpenWrt, it writes the build you tried into the stock firmware's
slot as well. Finish [Try](1-try.md) first, including [step 6](1-try.md#6-keep-the-trial-image) (`trial-commit`).

Run the commands on the kit computer, plugged into jack 1 of the unit. `root@192.168.1.1` is the unit while it runs
OpenWrt; `$STAMP` is the build ID of the build you tried (a directory under `out/`).

## What this stage does

After stage 1, one slot holds the stock firmware (the stock slot) and the other holds the trial image you kept. This
stage:

1. saves the stock slot to a file on the kit computer (the stock backup);
2. writes the same build into the stock slot with `./device.sh upgrade` (OpenWrt's sysupgrade), carrying your
   settings over, and starts it from there;
3. checks the result and keeps the new slot.

Afterwards both slots hold OpenWrt, and the stock firmware exists only as the backup file. The way back to it is
[restoring that file](4-going-back.md#restore-the-stock-firmware-from-the-backup), which runs from OpenWrt: if
neither slot starts OpenWrt any more, there is no supported or tested way back (no serial-console recovery
procedure).

Tried on one unit, from slot B into slot A: the refusal without a backup and writing a normal image of another build
over the stock slot (2026-10-31), and this stage as described here with the current build, a trial image: backup,
the same build over the stock slot, `upgrade-check` and `trial-commit` (2026-11-01). With the stock firmware in slot B,
stage 2 has not been tried ([Status](reference/status.md)).

### Before you start

- **OpenWrt is kept and marked good.** In `./device.sh status root@192.168.1.1`, the line of the booted slot
  (`booted=`) shows `success=01`, `next=` names the same slot, and the status shows `root=rootfs_b` (for slot B) and
  `timer=committed` (a normal image shows `policy=normal` and no `timer=` line).
- **You have `out/$STAMP/` of that build**, with `sysupgrade.bin` in it. In a new shell, set the build ID again, for
  example `STAMP=20261031-192819-083d5306`.
- **Do not start the stock firmware between step 1 and step 2.** It changes its slot when it runs, and step 2 then
  refuses the backup.
- **With the modem**, this stage uses a new trial build for the stock slot's modem firmware instead of the build from
  stage 1, prepared before step 1, and its build ID as `$STAMP`
  ([Before Keep: a build for the stock slot](features/modem.md#before-keep-a-build-for-the-stock-slot)). Not tried on
  a unit.

## 1. Back up the stock slot

    ./device.sh stock-backup root@192.168.1.1

It reads the 15 partitions of the other slot, checks what it received, saves it as
`out/stock/air6-stock-<slot>-<time>-<id>.tar` and then confirms the backup on the unit: the unit records that the kit
checked and saved this file. A backup only reads the slot. On the tested unit it took about a minute and the file
was about 280 MiB. When it worked, the output ends with:

    saved out/stock/air6-stock-a-20261031-202303-30909ec2.tar
    ...
    confirmed on the unit

- **Ends with an error** (`... not confirmed`, or another message without `confirmed on the unit`): nothing was
  confirmed. The lines above it say why; fix that and run the backup again.
- **Says the backup is `NOT confirmed on the unit`:** the file is kept. Run the `ssh root@192.168.1.1 air6-stock
  confirm ...` line it prints (repeating it is safe). Step 2 is refused until the backup is confirmed.

Keep the file private and keep a safe copy elsewhere. It holds data specific to your unit, and once step 2 has run,
the unit cannot make it again. The confirmation on the unit does not prove that the file still exists.

The confirmation counts only while the stock slot stays as it was, and only on the OpenWrt that took it:

- Take the backup again after every start of the stock firmware: it changes its `mcf1` and `mcf2` partitions, and
  step 2 then refuses the older backup.
- Take it from the OpenWrt that runs step 2. The confirmation is kept in the settings of the running OpenWrt slot, and
  an update does not carry it over.

How the backup and its check work: [reference/stock-backup.md](reference/stock-backup.md).

## 2. Write OpenWrt into the stock slot

**This step removes the stock firmware from its slot. Afterwards it exists only as the backup file.** Before you run
it:

- Copy `out/stock/air6-stock-<slot>-<time>-<id>.tar` off the kit computer. It is inside the kit directory: deleting
  that directory deletes it.
- The stock firmware has not run since step 1 (otherwise the unit refuses; take the backup again).
- The way back needs OpenWrt to start in at least one slot:
  [restoring the backup](4-going-back.md#restore-the-stock-firmware-from-the-backup).

Then:

    ./device.sh upgrade root@192.168.1.1 $STAMP

The unit first checks the package and its own state. Because the other slot holds the stock firmware, it also checks
that slot against the confirmed backup; the output shows `verify slot a: OK, the 13 partitions match the confirmed
backup ...` (`slot b` if the stock firmware is in slot B). When a check fails, nothing is written and the output ends
with `the unit refused the package (see above); nothing was written`; see
[When the unit refuses](3-update.md#when-the-unit-refuses).

When the checks pass, the output ends with:

    sysupgrade request sent (request recorded in out/20261031-192819-083d5306/upgrade-request-...). ...
    The unit stops its services, writes slot a and reboots into it (1 to 3 minutes).
    Then run: ./device.sh upgrade-check root@192.168.1.1 20261031-192819-083d5306
    If it does not come back and the power LED blinks red, see docs/troubleshooting.md (sysupgrade stopped).

The unit then stops its services, writes the build into the stock slot, carries your settings over and reboots into
that slot. Allow 1 to 3 minutes, and leave the power on: a power cut during an update has not been tried.
How the update checks and writes the slot: [reference/sysupgrade.md](reference/sysupgrade.md).

If the unit does not come back and the power LED blinks red, see
[sysupgrade stopped](troubleshooting.md#sysupgrade-stopped).

## 3. Check the result

Once the unit answers again (if `upgrade-check` cannot connect yet, wait and run it again):

    ./device.sh upgrade-check root@192.168.1.1 $STAMP

It prints the status of the unit, then the result. The result expected here starts with:

    result: written, and the unit runs the new slot a on rootfs_a (a normal image is marked good once ...

For any other result, see the [result table](3-update.md#check-the-result). If the result is "failed", a write into
the stock slot was started or may have been: do not assume the stock firmware there is still usable, and keep the
backup file ([sysupgrade stopped](troubleshooting.md#sysupgrade-stopped)).

The build is a trial image, as in stage 1, so the new slot is a trial again: the status shows `policy=trial` and
`timer=armed, returns to slot b in ...s` (the time left). Within 10 minutes of the reboot into the new slot:

1. Check that it works, as in [Try, step 5](1-try.md#5-check-that-it-works). The settings came over from stage 1,
   including the root password and the SSH host keys: log in as before. Keeping marks the slot good, and "good" only
   means that start-up finished: it does not check that the network works.
2. Keep it:

       ./device.sh trial-commit root@192.168.1.1

   The output shows `slot a committed`.

Then `./device.sh status root@192.168.1.1` shows `success=01` on the lines of both slots. (With a normal image,
`success=01` appears once start-up has finished; there is nothing to keep.)

If you do not keep it in time and the status shows `timer=armed`, the unit returns to the OpenWrt in the other slot
about 10 minutes after start-up (until it is kept, two warm reboots return it as well:
[With a trial image](3-update.md#with-a-trial-image)). The stock slot then
holds this build, not marked good; the stock firmware is gone from it either way. To try again, run step 2 again: no
new backup is needed, because the slot no longer holds the stock firmware.

## After this

- **Both slots hold OpenWrt**, both marked good. OpenWrt runs from the former stock slot. The other slot holds the
  build you kept in stage 1 (the same build, unless you made a separate one for the modem), with its settings as they
  were at the update; [starting the other slot](4-going-back.md#start-the-other-slot) starts it.
- **The stock firmware exists only as the backup file.** Keep it private and keep a safe copy. The way back is
  [restoring it](4-going-back.md#restore-the-stock-firmware-from-the-backup), from OpenWrt.
- **Across reboots:** at every start-up that finishes, OpenWrt marks its slot as good again, and the bootloader keeps
  booting it.
- **Settings** stay in the OpenWrt slot (about 120 MiB, in the same partition as the system). OpenWrt does not use the
  stock firmware's data partition (`user_data`, about 3 GiB): do not format that partition, the stock firmware keeps
  its data there.
- **Packages** you add with `apk` must come from the build whose image the unit runs; see
  [build.md](build.md#what-a-build-leaves-behind). Updates do not carry them over.

Next: later builds go in with [Update](3-update.md). To go back at any time, see [Going back](4-going-back.md).
