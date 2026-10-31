# Technical reference

These pages describe what the OpenWrt fork and this kit add for the Air 6, one page per mechanism: what the code does
now and what was tested. The stage pages ([try](../1-try.md), [keep](../2-keep.md), [update](../3-update.md),
[go back](../4-going-back.md)) say what to do; read this page first when you want to know why.

## Overview

- **Two slots.** The unit has two system slots, A and B. Each slot has its own boot image, root file system and
  firmware partitions; some partitions, such as `misc` and the stock firmware's data partition `user_data`, are
  shared ([partitions](partitions.md)).
- **The bootloader picks the slot.** It reads 10 boot control bytes in `misc`: per slot a priority, a retry count
  and a success flag. It boots the slot with priority `0f` and counts that slot's warm boots; when the count reaches
  its limit, it starts the other slot instead. OpenWrt resets the count of its own slot at the end of a normal
  start-up. A slot therefore reaches the limit when it does not finish a normal start-up: it crashes, it runs in
  failsafe mode, its `root=` is wrong, or it is a trial image rebooted before it is kept
  ([boot control](boot-control.md)).
- **Marked good.** A slot is marked good when its success flag is `01` (`success=01` in the status; the tools call
  it "successful"). OpenWrt marks its slot good at the end of every normal start-up that finishes. A trial image does
  not, until you keep it. "Good" only means that start-up finished: it does not check that the network works.
- **Writing a slot.** The install writes the slot the stock firmware is not running from. From OpenWrt, sysupgrade
  ([sysupgrade](sysupgrade.md)) and the restore of the stock firmware from a backup ([stock backup](stock-backup.md))
  write the slot OpenWrt is not running from.
- **The stock firmware stays in its slot only until something overwrites it.** The first `./device.sh upgrade`
  does. From then on the other slot holds the previous OpenWrt, and the stock firmware exists only as the backup file.

Ways out when something goes wrong. "The other slot" is the stock firmware while it is still in a slot, and the
previous OpenWrt after the first update.

| Situation | Way out | Ends in | Tried on one unit |
| --- | --- | --- | --- |
| OpenWrt crashes or hangs, and the unit resets before start-up finishes | Automatic: the bootloader starts the other slot after a few failed attempts ([how many](boot-control.md#how-the-bootloader-uses-them)) | The other slot | Yes (a root file system erased by a test script, 2026-10-17; after an update only as two warm reboots of a trial image) |
| A trial image is not kept | Automatic: about 10 minutes after start-up, when its return timer is armed ([trial images](boot-control.md#trial-images)) | The other slot | Yes |
| OpenWrt runs and you can log in | `air6-slot set-active` and a reboot ([choosing the next slot](boot-control.md#choosing-the-next-slot)) | The other slot (it must be marked good) | Yes |
| OpenWrt starts, but its settings make it unreachable | Failsafe mode with the WPS key ([failsafe mode](keys-and-failsafe.md#failsafe-mode)) | The same OpenWrt, without your settings | Yes (entered; not reached from a computer) |
| OpenWrt starts, but the build itself does not work | Hold the LEVEL key at power-on ([LEVEL key](keys-and-failsafe.md#switching-slots-with-the-level-key)) | The other slot (it must be marked good) | Yes |
| The stock firmware is no longer in a slot | Restore it from the backup, from OpenWrt ([stock backup](stock-backup.md)) | The stock firmware, in the slot of the backup | Yes |

There is no automatic way back for an image that hangs before start-up finishes without the unit resetting. Pulling
the power does not count as a failed attempt, so power cycling does not bring the other slot back. Once both slots
hold OpenWrt, if neither starts any more, there is no supported or tested way back: the restore of the stock firmware
runs from OpenWrt.

What "Tried on one unit" covers, with dates and builds: [status](status.md).

## Pages

| Page | What it covers |
| --- | --- |
| [status.md](status.md) | What was tested on a unit, what was not, and what is not supported |
| [boot-control.md](boot-control.md) | The boot control bytes, the bootloader's retry rule, marking a slot good, trial images, `air6-slot` |
| [keys-and-failsafe.md](keys-and-failsafe.md) | The RESET, WPS and LEVEL keys, failsafe mode, switching slots with the LEVEL key |
| [sysupgrade.md](sysupgrade.md) | Updating OpenWrt into the other slot |
| [stock-backup.md](stock-backup.md) | Backing up a stock firmware slot and restoring it |
| [partitions.md](partitions.md) | The partitions of the two slots and the shared ones |
| [hardware.md](hardware.md) | The hardware of the Air 6 as far as this port uses it |
