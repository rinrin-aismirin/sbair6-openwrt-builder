# Going back

This page is stage 4, for any time after [Try](1-try.md): starting the other slot, getting the stock firmware back, or
starting the same OpenWrt again from the stock firmware. Start with [Which way back](#which-way-back).

Run the commands on the kit computer, plugged into jack 1 of the unit. `root@192.168.1.1` is the unit while it runs
OpenWrt; `root@DEVICE` is the unit while it runs the stock firmware (its address on your network, reachable with root
SSH); `$STAMP` is a build ID (a directory under `out/`).

## Which way back

`./device.sh status root@192.168.1.1` shows which slot OpenWrt runs from (`booted=`) and whether the other slot is
marked good (`success=01` on its line). What the other slot holds depends on the stage you reached:

| You want | When | Go to |
| --- | --- | --- |
| The stock firmware | It is still in the other slot (after [Try](1-try.md), before [Keep](2-keep.md)) | [Start the other slot](#start-the-other-slot) |
| The stock firmware | No slot holds it any more (after [Keep](2-keep.md)) | [Restore the stock firmware from the backup](#restore-the-stock-firmware-from-the-backup) |
| The OpenWrt in the other slot (after [Keep](2-keep.md): the build you kept in stage 1, with its older settings; after an [update](3-update.md): the previous build) | The other slot is marked good | [Start the other slot](#start-the-other-slot) |
| OpenWrt again, from the stock firmware | The other slot still holds OpenWrt | [Boot the same OpenWrt again](#boot-the-same-openwrt-again) |
| Out of an OpenWrt you cannot reach | | [When you cannot reach the unit](recovery.md) |
| Out of an image built with an earlier kit | `device.sh` refuses it (older image, or no sysupgrade support) | [Units with an image from an earlier kit](#units-with-an-image-from-an-earlier-kit) |

While the stock firmware runs, it may update itself. A stock firmware update writes the slot it is not running from,
which is the OpenWrt slot (read from the stock update script; not observed).

## Start the other slot

The other slot must be marked good: its line in the status shows `success=01`. For example, with OpenWrt in slot B,
select slot A (from another computer on jack 1: `ssh root@192.168.1.1 air6-slot set-active a`):

    ./device.sh set-active root@192.168.1.1 a

`set-active` does not reboot; it also stops a running trial timer (`timer=cancelled`). When it worked, the output is:

    slot a boots next (bootctrl ... -> ...)
    next: ./device.sh reboot root@192.168.1.1

(Over ssh, only the first line.) **Anything else: stop here, do not reboot.** It changes nothing and refuses when it
says:

- `slot a is not marked successful; not selecting it`: the other slot is not marked good, for example a trial image
  that was not kept, or a failed update.
- `an update of the other slot is in progress`: a stock backup or restore is running. After an interrupted one, the
  refusal stays until the next reboot.

For `write of ... failed`, a dropped connection or any other ending, see
[set-active or switch stops](troubleshooting.md#set-active-or-switch-stops).

Only after the success lines, reboot (from another computer: `ssh root@192.168.1.1 reboot`):

    ./device.sh reboot root@192.168.1.1

After the reboot:

- **The stock firmware was in that slot:** the unit starts the stock firmware, at `root@DEVICE`. OpenWrt stays in its
  slot; [Boot the same OpenWrt again](#boot-the-same-openwrt-again) returns to it. The stock firmware changes its slot
  while it runs: before [Keep](2-keep.md), take a new stock backup.
- **OpenWrt was in that slot:** the previous build starts at 192.168.1.1, with its own settings as they were when it
  last ran.

When you cannot reach OpenWrt over the network, holding the LEVEL key at power-on switches to the other slot in the
same way: see
[switch slots with the LEVEL key](recovery.md#the-build-itself-does-not-work-switch-slots-with-the-level-key) for
the steps and [keys and failsafe](reference/keys-and-failsafe.md) for how it works. All ways out of an unreachable
unit: [docs/recovery.md](recovery.md).

## Restore the stock firmware from the backup

You need:

- the backup file from [Keep, step 1](2-keep.md#1-back-up-the-stock-slot),
  `out/stock/air6-stock-<slot>-<time>-<id>.tar`; the letter after `air6-stock-` is the slot it came from;
- OpenWrt running from the other slot than the backup's, marked good and booting next (with a trial image, run
  `./device.sh trial-commit root@192.168.1.1` first; after `set-active`, reboot first);
- the kit computer on jack 1.

If `booted=` in the status is the backup's slot (the letter in the file name), as right after [Keep](2-keep.md),
[start the other slot](#start-the-other-slot) first. That slot must hold an OpenWrt that is marked good. The restore
runs from OpenWrt: if neither slot starts OpenWrt any more, there is no supported or tested way back (no
serial-console recovery procedure).

    ./device.sh restore-stock root@192.168.1.1 out/stock/air6-stock-<slot>-<time>-<id>.tar

`restore-stock` checks the file on the kit computer, uploads part of it, and writes only `mcf1`, `mcf2`, `boot` and
`rootfs` of the backup's slot. Before writing, it refuses when the slot's other 11 partitions (modem and bootloader
firmware among them; never written) differ from the backup, when the backup is from another unit, when OpenWrt runs
from the backup's slot, or when OpenWrt's own slot is not marked good. It does not reboot. When it worked (about a
minute on the tested unit), the output ends with:

    slot a is the next boot slot as a trial (retry preset 02): if the restored stock does not come up after a few
    attempts, the preloader returns to slot b
    next: ./device.sh reboot root@192.168.1.1

**Anything else: stop here, do not reboot.** Read [The stock restore stops](troubleshooting.md#the-stock-restore-stops)
before you reboot or run it again.

Only after these lines, reboot:

    ./device.sh reboot root@192.168.1.1

After the reboot the restored stock firmware starts with its retry count preset to 02; if it does not come up, the
bootloader returns to the OpenWrt slot after a few attempts
([details](reference/boot-control.md#how-the-bootloader-uses-them); a failed start after a restore has not been
tried). The settings stored in the backed-up root file system come back with it. The shared NV partitions and
`user_data` are not restored and keep their current contents
([what is restored](reference/stock-backup.md#what-is-saved)).
`./device.sh status root@DEVICE` then shows the restored slot as `bootslot=`. OpenWrt stays in its slot
([Boot the same OpenWrt again](#boot-the-same-openwrt-again)).

What has been tried, on one unit: a backup and a restore of the same bytes into a slot that still held the stock
firmware (2026-10-30), and a restore into a slot that OpenWrt had overwritten by sysupgrade (2026-10-31, and on
2026-11-01 with the current build). On 2026-10-30 and 2026-10-31 the restored stock firmware started on the first
try, and on 2026-10-31 its modem found the SIM as before the overwrite; on 2026-11-01 it started and marked its slot
good.
Mobile data on the restored stock firmware has not been tried.

How the backup and the restore work: [reference/stock-backup.md](reference/stock-backup.md).

## Boot the same OpenWrt again

From the stock firmware, while the other slot still holds OpenWrt, without installing again. You need `out/$STAMP/` of
the build that slot holds: the build you last installed or updated into it.

    ./device.sh switch root@DEVICE $STAMP

`switch` checks that the boot partition of the OpenWrt slot matches `out/$STAMP/boot.img`; it does not check the rest
of the slot. When it worked, the output ends with:

    slot b preferred, retry preset 02
    next: ./device.sh reboot root@DEVICE

(`slot a` if OpenWrt is in slot A.) **Anything else: stop here, do not reboot.**

- **`abort: boot_b is not the expected image`:** the slot holds another build; nothing was changed. Run `switch` with
  the build ID of the build in that slot.
- **`abort: ...` for another reason:** a check failed before anything was changed.
- **`UNEXPECTED bootctrl`, a dropped connection, or any other ending:**
  [set-active or switch stops](troubleshooting.md#set-active-or-switch-stops).

Only after the success lines, reboot:

    ./device.sh reboot root@DEVICE

The slot starts like a fresh install: a trial image arms its return timer again, a normal image is marked good at the
end of start-up. Continue as in [Try, step 4](1-try.md#4-reboot-and-connect).

The stock firmware changed its slot while it ran: before [Keep](2-keep.md), take a new stock backup.

## Units with an image from an earlier kit

Earlier kits never wrote the stock firmware's slot, so on such a unit the stock firmware is still in the other slot.
Go back to it, then install a new build from the stock firmware as in [Try, step 3](1-try.md#3-install).

- **The image has `air6-abguard` instead of `air6-slot`:** the current `device.sh` refuses it (`runs an older OpenWrt
  image (air6-abguard)`). Go back with `ssh root@192.168.1.1 air6-abguard revert` (what the earlier kit's `to-stock`
  did). Only when it prints `slot a made preferred (slot b prio 0e)` (or the other way round), reboot with
  `ssh root@192.168.1.1 reboot`. An `error:` line: stop here, do not reboot, and keep the output.
- **The image has `air6-slot` but no sysupgrade support:** `upgrade` refuses it (`runs an image without sysupgrade
  support`), and `stock-backup` and `restore-stock` refuse an image without `/usr/sbin/air6-stock`. Go back with
  [Start the other slot](#start-the-other-slot).
