# Installing and removing OpenWrt

This page walks through one install from the start: choosing what to build, building, installing, the first login,
and later updating, going back to the stock firmware or recovering. Read the warning at the top of the
[README](../README.md) first.

## How it works

The Air 6 has two system slots, A and B. The stock firmware runs from one of them. The install writes OpenWrt into
the other slot and tells the bootloader to try it next. The stock firmware's slot is never written, so it stays as
the way back. After the first update ([Updating](#updating-to-a-new-build)) the other slot holds the previous OpenWrt
instead; everything below that returns to "the other slot" then returns to that previous OpenWrt.

When a normal image finishes starting, it marks its slot as good (`success=01` in the status; the tools call it
"successful"), and the bootloader keeps booting it from then on. "Good" only means that start-up finished: it does
not check that the network works.

Ways out when an install goes wrong:

| Situation | Way out | Ends in | Tried on one unit |
| --- | --- | --- | --- |
| OpenWrt crashes or hangs, and the unit resets before start-up finishes | Automatic: right after an install or update the bootloader gives up after two attempts (about 2 minutes each) | The other slot (before the first update: the stock firmware) | Yes |
| A trial image (see [step 1](#1-choose-what-to-build)) is not kept | Automatic: 10 minutes after start-up, when its return timer is armed | The other slot | Yes |
| OpenWrt starts, but its settings make it unreachable | Failsafe mode with the WPS key ([below](#openwrt-starts-but-you-cannot-reach-it)) | The same OpenWrt, without your settings | Yes (entered; not reached from a computer) |
| OpenWrt starts, but the build itself does not work | Hold the LEVEL key at power-on ([below](#openwrt-starts-but-you-cannot-reach-it)) | The other slot | Yes |

There is no automatic way back for an image that hangs before start-up finishes without the unit resetting. Pulling
the power does not count as a failed attempt, so power cycling does not bring the other slot back.

In the commands below, `root@DEVICE` is the unit while it runs the stock firmware (its address on your network,
reachable with root SSH), and `root@192.168.1.1` is the unit while it runs OpenWrt, from a computer on jack 1.
`./device.sh ... root@192.168.1.1` therefore needs the kit's computer on jack 1; from another computer on jack 1,
run the `air6-slot` command shown next to it over `ssh root@192.168.1.1`. `$STAMP` is the build ID, the name of a
directory under `out/`.

## 1. Choose what to build

Decide these before you build; they cannot be added to an image that is already built.

- **Normal or trial image.** Use a trial image for a build that has not run on your unit before. A trial image is
  not marked good at the end of start-up: early in start-up it arms a timer, and unless you keep it (step 6) it
  switches back to the other slot 10 minutes later and reboots. The timer is only armed when the other slot is
  marked good (the stock firmware's slot is, after a normal stock boot). A normal image marks its slot as good as soon as
  it finishes starting.
- **Your SSH key and settings.** Files under `local/files/` go into the image, for example your public key in
  `local/files/etc/dropbear/authorized_keys`. Without a key, the first login is as root with no password (OpenWrt's
  default). See [docs/build.md](build.md#customizing-the-image).
- **Optional features.** The modem needs files from your unit before the build ([docs/modem.md](modem.md)). A USB
  2.5G adapter needs a build option ([docs/usb-nic.md](usb-nic.md)).

## 2. Build

Get the kit and run all later commands in its directory:

    git clone https://github.com/rinrin-aismirin/sbair6-openwrt-builder.git
    cd sbair6-openwrt-builder

If your Docker runs under a context other than the current one (for example rootless Docker), set it first:

    export DOCKER_CONTEXT=rootless

Then build. A full build took about 15 minutes on a 32-thread machine, including the downloads.

    ./build.sh image                   # the Docker image the build runs in (once)
    ./build.sh fetch                   # the OpenWrt fork, at the commit pinned in fork.lock
    ./build.sh pull-fw root@DEVICE     # the Wi-Fi firmware from your unit (once)

Start one build. For a trial image (recommended for a first install):

    STAMP=$(./build.sh start --trial)

For a normal image, use this line instead:

    STAMP=$(./build.sh start)

Options from [docs/modem.md](modem.md) or [docs/usb-nic.md](usb-nic.md) go into this same `start` command. Then:

    echo $STAMP                        # the build ID, for example 20261024-224537-75026e36; note it
    ./build.sh status $STAMP           # repeat until the last line says "result: done"
    ./build.sh collect $STAMP          # copies the result to out/$STAMP/; it must print "RESULT: PASS"

While a build runs, do not change this directory (including `local/`) or the fork checkout. If `status` says
`result: failed`, see [docs/build.md](build.md#build-steps-and-failures). In a new shell, set the build ID again
before using it: `STAMP=20261024-224537-75026e36`.

## 3. Install

Check the build and the unit:

    tail -n 1 out/$STAMP/CHECK.txt     # must say RESULT: PASS; install refuses builds that did not pass
    grep policy out/$STAMP/CHECK.txt   # "trial" or "normal", as chosen in step 1
    ./device.sh status root@DEVICE

On the stock firmware, `status` prints the running slot and the boot control bytes, for example:

    00:03:51 bootslot=a uptime=959.17 bootctrl=0f000101000e00010100

`bootslot=a` means the stock firmware runs from slot A, so OpenWrt will go into slot B. (The bytes are explained in
[Technical notes](#technical-notes).)

Install:

    ./device.sh install root@DEVICE $STAMP

This uploads the two image files (160 MiB) and writes them into the other slot. It does not reboot. When it worked,
the output ends with:

    boot_b and rootfs_b written and verified
    ...
    slot b preferred, retry preset 02
    installed; next: ./device.sh reboot root@DEVICE

(`slot a` instead of `slot b` if the stock firmware runs from slot B.) **If it ends any other way, do not reboot**;
see [When something goes wrong](#when-something-goes-wrong).

Keep `out/$STAMP/` after installing: booting this build again later needs it.

## 4. Reboot and connect

Before rebooting:

- Plug a computer into jack 1. With OpenWrt's defaults it should get an address in 192.168.1.0/24 (these defaults
  have not been tried on a unit yet). If that computer is also connected to another network that uses
  192.168.1.0/24, disconnect it.
- OpenWrt has new SSH host keys. If that computer connected to 192.168.1.1 before, remove the old entry now, so ssh
  does not refuse later: `ssh-keygen -R 192.168.1.1`.

Then reboot. With a trial image, the 10 minutes for steps 5 and 6 start now.

    ./device.sh reboot root@DEVICE

OpenWrt took about 70 seconds to answer in our tests. Log in with `ssh root@192.168.1.1` or open LuCI at
http://192.168.1.1. Without a key in the image, root has no password: set one with `passwd`.

Then look at the slots (from another computer: `ssh root@192.168.1.1 air6-slot status`):

    ./device.sh status root@192.168.1.1

The output starts like this (here OpenWrt runs from slot B):

    booted=b
    next=b
    slot a: prio=0e retry=00 success=01 uptype=01
    slot b: prio=0f retry=00 success=01 uptype=01
    root=rootfs_b
    policy=normal

- Normal image (`policy=normal`): the line of the slot it runs from (`booted=`) shows `success=01` once start-up has
  finished.
- Trial image (`policy=trial`): that slot stays `success=00`, and `timer=armed, returns to slot ... in ...s` shows
  that the return timer runs. See [step 6](#6-trial-image-keep-it) for the other `timer=` values.
- `WARNING: ...` instead of `root=rootfs_b`: the image boots another slot's root file system; it is not marked good.
  Do not update from this state.

If the unit comes back with the stock firmware instead, OpenWrt did not start (or, with a trial image, was not kept
in time). The stock firmware and its slot are unchanged; you can try again from step 3.

## 5. Check that it works

From the computer on jack 1 (`ssh root@192.168.1.1`):

- Plug the internet connection into jack 2 (WAN). `ip -4 addr show wan` should show an address, and
  `ping -c 3 openwrt.org` should answer (expected with the defaults; not yet seen on a unit).
- `cat /tmp/sysinfo/board_name` says `softbank,air6`.
- Optional: plug in a USB memory stick. `dmesg | tail` shows it, and `ls /dev/sd*` lists the disk and its
  partitions.

For a closer look:

- `dmesg | grep mt7996e` shows the Wi-Fi firmware build times. With the firmware listed in `stock-firmware.lock`
  they are: ROM patch `20230704161925a`, WM `20240315201529`, DSP `20231113135337`, WA `20240315201449`. If your
  firmware had another hash (`pull-fw` warned about it), other times are expected; check `out/$STAMP/PROVENANCE`.
  There must be no `eeprom load fail`, `no valid board EEPROM` or `timeout` lines.
- `dmesg | grep "PCS detected"` shows two lines: the Ethernet links to the switch were found.

Wi-Fi is off until you turn it on in LuCI or with `uci`. Read the warning in the README first.

## 6. Trial image: keep it

Only for a trial image, and only when you want to keep it after the checks above. Within 10 minutes of the reboot:

    ./device.sh trial-commit root@192.168.1.1

or, from another computer, `ssh root@192.168.1.1 air6-slot trial commit`. The output shows `slot b committed`
(or `slot a`). From then on the image behaves like a normal one.

If you do nothing and the status shows `timer=armed`, the unit returns to the other slot 10 minutes after
start-up (`timer=armed, due ...s ago` means the return is under way). Other `timer=` values:

| Value | Meaning |
| --- | --- |
| `committed` | Kept; no return |
| `cancelled` | A slot was chosen by hand (`set-active`); no return |
| `fired` | The other slot is already selected; a reboot follows |
| `none`, `no-fallback`, `not-armed`, `error`, `overdue` | No return will happen by itself; keep the image or [go back by hand](#going-back-to-the-stock-firmware) |

## Optional features after the install

With either image: built with the modem, continue with [docs/modem.md](modem.md) (NV backup first); built with the
USB adapter driver, check it as in [docs/usb-nic.md](usb-nic.md).

## Across reboots

A normal image marks its slot as good again at every boot that finishes starting. A kept trial image does the same.
Until a trial image is kept, the bootloader also counts its warm reboots (pulling the power does not count): right
after an install or update, one more reboot starts OpenWrt again and the one after that starts the other slot.

## Settings and packages

OpenWrt keeps its settings in its own slot (about 120 MiB). It does not use the stock firmware's data partition
(`user_data`, about 3 GiB): do not format that partition, the stock firmware keeps its data there.

Packages you add with `apk` must come from the build whose image the unit runs; see
[docs/build.md](build.md#what-a-build-leaves-behind).

## Going back to the stock firmware

While the other slot still holds the stock firmware (before the first update), `set-active` and a reboot start it.
After the first update, the same commands start the previous OpenWrt build; the stock firmware then comes back only
by [restoring the backup](#restoring-the-stock-slot-from-the-backup).

`./device.sh status root@192.168.1.1` shows which slot OpenWrt runs from (`booted=`). For example, with OpenWrt in
slot B:

    ./device.sh set-active root@192.168.1.1 a
    ./device.sh reboot root@192.168.1.1

(From another computer: `ssh root@192.168.1.1 air6-slot set-active a`, then `ssh root@192.168.1.1 reboot`.)

The unit reboots into the stock firmware. OpenWrt stays in its slot. `set-active` refuses a slot that is not marked
good ("not marked successful").

While the stock firmware runs, it may update itself, and an update overwrites the OpenWrt slot (see the README).

A unit that runs an image built with an earlier version of this kit has `air6-abguard` instead of `air6-slot`, and
the current `device.sh` refuses it. Go back with `ssh root@192.168.1.1 air6-abguard revert` and
`ssh root@192.168.1.1 reboot` (what the earlier kit's `to-stock` did), then install a new build.

### Backing up the stock slot

The way back above needs the stock firmware in the other slot. Once something overwrites that slot (the first
`./device.sh upgrade` does), the stock firmware can only come back from a backup.
Take it from OpenWrt:

    ./device.sh stock-backup root@192.168.1.1

It reads the 15 partitions of the other slot, checks what it received, saves it as
`out/stock/air6-stock-<slot>-<time>-<id>.tar` and then confirms the backup on the unit. When it worked, the output
ends with `confirmed on the unit`. If it says the backup is NOT confirmed, the file is kept; run the
`ssh ... air6-stock confirm ...` line it prints.

- Take it before anything overwrites the last slot that holds the stock firmware. `./device.sh upgrade` (sysupgrade)
  refuses to write that slot without a confirmed backup that still matches it.
- Take it again after every boot of the stock firmware. The stock firmware changes its `mcf1` and `mcf2` partitions
  when it runs, and the check then refuses the older backup.
- Keep the file private and keep a safe copy. It holds data specific to your unit, and the unit cannot make it again
  once the stock slot is overwritten. The confirmation on the unit only records that the kit checked and saved the
  file; it does not prove that the file still exists.

### Restoring the stock slot from the backup

From OpenWrt running in the other slot than the backup's (the file records its slot):

    ./device.sh restore-stock root@192.168.1.1 out/stock/air6-stock-<slot>-<time>-<id>.tar
    ./device.sh reboot root@192.168.1.1

`restore-stock` writes only `mcf1`, `mcf2`, `boot` and `rootfs` of that slot, from the file. Before writing, it
refuses when the slot's other 11 partitions (modem and bootloader firmware among them; never written) differ from the
backup, when the backup is from another unit, or when OpenWrt's own slot is not marked good (with a trial image, run
`./device.sh trial-commit` first). It does not reboot; when it worked, the output ends with `next: ./device.sh reboot ...`.

After the reboot the restored stock firmware gets two tries; if it does not come up, the unit returns to the OpenWrt
slot. It comes back with the settings it had when the backup was taken (for example the SIM lock), not later ones.
OpenWrt stays in its slot ([Booting the same OpenWrt again](#booting-the-same-openwrt-again)).

What has been tried, on one unit: a backup and a restore of the same bytes into a slot that still held the stock
firmware (2026-10-30), and a restore into a slot that OpenWrt had overwritten by sysupgrade (2026-10-31). Both times
the restored stock firmware started on the first try; the second time its modem found the SIM as before the overwrite.
Mobile data on the restored stock firmware has not been tried.

If the restore stops, see [The stock restore stops](#the-stock-restore-stops).

## Booting the same OpenWrt again

From the stock firmware, without installing again:

    ./device.sh switch root@DEVICE $STAMP
    ./device.sh reboot root@DEVICE

`switch` checks that the boot partition of the OpenWrt slot matches `out/$STAMP/boot.img`; it does not check the
rest of the slot. The slot starts like a fresh install (a trial image arms its timer again). Continue as in step 4.

## Updating to a new build

You need the kit computer on jack 1 and the build directory `out/$STAMP/` (the `upgrade` commands do not work from
another computer). The build must have `out/$STAMP/sysupgrade.bin` (kits from this version on), and the unit must run
an image with sysupgrade support: on an older image `ssh root@192.168.1.1 ls /lib/air6/upgrade.sh` fails, and the new
build has to be installed once from the stock firmware ([going back](#going-back-to-the-stock-firmware), then steps 3
to 6).

**Before the first update:** it overwrites the stock firmware (OpenWrt alternates between the two slots from then
on). The unit refuses unless the stock slot has a confirmed backup that still matches it: take a new backup right
before ([Backing up the stock slot](#backing-up-the-stock-slot)) and keep the file safe.

Then:

    ./device.sh upgrade root@192.168.1.1 $STAMP

It uploads `sysupgrade.bin`, lets the unit check it (`sysupgrade -T`; nothing is written when that fails, and the
output ends with "the unit refused the package (see above)" after the unit's reason), records the request in
`out/$STAMP/upgrade-request-<time>`, then starts sysupgrade. The unit stops its services, writes the build into the
other slot, carries your settings over, and reboots into the new slot. Allow 1 to 3 minutes.

- **Settings** are what OpenWrt's sysupgrade keeps: `/etc/config`, the files listed in `/etc/sysupgrade.conf` and the
  configuration files of packages (`ssh root@192.168.1.1 sysupgrade -l` lists them), including the SSH host keys.
  Other files and packages you added with `apk` are not carried over.
- **`--no-config`** (`./device.sh upgrade root@192.168.1.1 $STAMP --no-config`, the option last) does not carry the
  current settings over: the new slot starts with the defaults built into that image. Files and uci-defaults included
  through `local/files` still apply; where the image does not change them, that means OpenWrt's default network, new
  SSH host keys (`ssh-keygen -R 192.168.1.1` before connecting, as in [step 4](#4-reboot-and-connect)) and no root
  password. Not tried on a unit.

The unit logs each step of the update and, at the next start-up, keeps the result in the slot that started ("last
sysupgrade record" in `status`). A power cut before that start-up (a cold boot) loses it. Once the unit answers again
(if `upgrade-check` cannot connect yet, wait and run it again):

    ./device.sh upgrade-check root@192.168.1.1 $STAMP

It compares the record with the request (same unit boot, same image) and the root file system with the booted slot:

| `upgrade-check` says | Meaning | Next |
| --- | --- | --- |
| written, and the unit runs the new slot on its rootfs | The update finished and the new slot started | A normal image is marked good once start-up has finished (`success=01` in the status); a trial image needs `trial-commit` within 10 minutes (below) |
| written, but the unit runs the old slot again | The write finished, and the unit is back on the old slot; why is not known from this alone (an uncommitted trial image, a switch back, or failed starts). Seeing this needs the record to survive the restarts, which has not been tried | Check `status`: "failed updates", what you did, the timer |
| refused or failed | Nothing was activated; the old slot stays next. "refused": nothing was written. "failed": a write was started or may have been (see [sysupgrade stopped](#sysupgrade-stopped)) | Fix the cause shown in the record, then `upgrade` again |
| anything else (MISMATCH, "not rootfs_X", incomplete) | Not an expected state | Do not run `upgrade` again; keep the output and check `status` |

UNKNOWN means the result of this request is not known (no record of it on the running slot; in the two return tests
on the unit it was UNKNOWN both times). `upgrade-check` then adds what the status shows; these lines describe the
slots now, not the result of the request:

| Line after UNKNOWN | What it shows | Next |
| --- | --- | --- |
| "listed under 'failed updates'" | The other slot reached the bootloader's retry limit before it was marked good. An uncommitted trial image that was rebooted twice gives the same entry, and the entry may be from an earlier attempt | Decide from what you did; `upgrade` again if you want the build |
| "not marked good, retry .." | The other slot was selected for a boot after the write and is not marked good; whether it started, and where its record is, are not known | If you know a trial timer returned the unit: `upgrade` again and keep it in time |
| "whether it was started is unknown" | No evidence either way | Check `status`; `upgrade` again only if the booted slot is next and `success=01` |
| "runs slot X, not the slot the request came from" | The unit runs the other slot; which image it runs is not confirmed | Check `root=rootfs_X`, `policy=`, `timer=` and that it works; with a trial image, `trial-commit` after the checks |

**With a trial image** the new slot stays `success=00` and its return timer runs from the reboot (`timer=armed` in
the status). Check it as in step 5, then keep it within 10 minutes with `./device.sh trial-commit root@192.168.1.1`
(step 6); otherwise the unit returns to the previous OpenWrt.

Once the new slot is marked good (a normal image that finished starting, or a trial image after `trial-commit`),
both slots hold a good OpenWrt build: `./device.sh set-active root@192.168.1.1 <other slot>` and a reboot start the
previous build again.

The unit refuses an update (nothing written; `-F` does not override any of these):

- without a confirmed, still matching backup when the other slot holds the stock firmware;
- while OpenWrt's own slot is not marked good (a trial image: `./device.sh trial-commit` first), or another slot is
  already selected for the next boot (after `set-active` without a reboot, or a fired trial timer);
- while a backup or a restore of the other slot runs;
- when the root file system is not the booted slot's rootfs (`WARNING` in the status), or the other slot cannot be
  read;
- for a build with the modem whose modem programs do not match the modem firmware in the other slot
  ([docs/modem.md](modem.md#updating-with-the-modem)).

LuCI's "Flash new firmware image" and a manual `sysupgrade` run the same checks on the unit, but were not tried, and
`upgrade-check` needs the request that `./device.sh upgrade` records: use `./device.sh upgrade`.

## When something goes wrong

### sysupgrade stopped

`upgrade-check` says refused or failed: nothing was activated, the old slot is still the next boot slot, and a partly
written new slot stays marked not good (neither `set-active` nor the LEVEL key selects it). Fix the cause shown in the
record and run `upgrade` again. "refused" means nothing was written. "failed" means a write was started (or may
have been) and the run did not finish. On the first update, the stock firmware's slot may then have changed or been
partly overwritten: do not assume it is still usable, keep the backup, and check the phase and the read-back values in
the record before retrying. If the record shows the invalidate step read back as requested, the slot is marked not
good and cannot be selected. The stock firmware comes back from the backup
([Restoring the stock slot](#restoring-the-stock-slot-from-the-backup)).

Back on the old slot with "written": the write finished; the reason for the return is in the status (see the
`upgrade-check` table above), not in the record.

The unit does not come back and the power LED blinks red: sysupgrade could not be sure which slot boots next (the
boot control bytes did not read back as expected or could not be read), so it stopped instead of rebooting. The
network is down in this state.

- With a serial console: the console shows the step, the last bytes read, the command that prints the 10 bytes, and a
  shell. Read the bytes as in [Technical notes](#technical-notes); `reboot -f` boots whatever they say, as a power
  cycle would.
- Without a serial console: unplug the power and plug it in again. The unit then boots whatever the boot control
  bytes say, which is what an automatic reboot would have done. Allow up to 5 minutes (a new slot that does not start
  gets two tries of about 2 minutes each), then run `./device.sh status root@192.168.1.1`. `upgrade-check` will say
  UNKNOWN, because a power cycle loses the record. Run `upgrade` again only when the status shows the booted slot as
  next and `success=01`. If the unit does not come back at all, only the serial console can show why. A power cycle
  out of this state has not been tried.

### The install stops

Messages from `./device.sh install`:

- `abort: ...`: a check failed before the OpenWrt slot or the boot control bytes were written, for example the unit
  does not run the stock firmware, an upload is incomplete, or the boot control bytes are not as expected. The
  slots and the boot control bytes are unchanged; only the uploaded files in `/tmp` on the unit were written.
- `WRITE VERIFY FAILED`: the data read back from the OpenWrt slot does not match the image. The boot control bytes
  were not changed, so the unit keeps booting the stock firmware. Run the install again.
- `UNEXPECTED bootctrl`: the slot was written, but the boot control bytes did not end up as expected. **Do not
  reboot.** The output contains a line starting with `rollback`; log in to the unit (`ssh root@DEVICE`) and run the
  command after `rollback (run on the unit before rebooting):`. It restores the previous bytes.

If the command ends in any other way (the connection drops, an SSH error, no `installed;` line at the end): do not
reboot. Keep the output, run `./device.sh status root@DEVICE`, and compare the bytes with the ones before the
install. If they are unchanged, run the install again. If they changed, the next boot may try the half-written slot;
use the `rollback` line if it was printed.

### The stock restore stops

`./device.sh restore-stock` exits with the restore's exit code (also shown as `rc N`):

- 3, 4 or 5 (`restore not done`): refused, busy or a read error. Nothing was written.
- 6 (`restore stopped after a change was started`): a write was started, but the restore did not end normally.
  Do not rerun it straight away. Read the `outcome:` lines (also shown by
  `ssh root@192.168.1.1 air6-stock result DIR`, unless the output says the result could not be saved) and run
  `./device.sh status root@192.168.1.1`:
  - `slot X stays unsuccessful (not selectable)`: the slot may be partly written, but neither `set-active` nor the
    LEVEL key selects it. Run `restore-stock` again with the same file.
  - `the boot control record is unchanged`: nothing selects the slot either; run `restore-stock` again.
  - `slot X was activated`: the slot was restored and boots next; only the end failed (for example the result
    could not be saved, or the update reservation remains, which keeps `set-active` refused until a reboot).
    Reboot with `./device.sh reboot root@192.168.1.1` as after a restore that worked.
  - `the next boot slot is uncertain`: do not reboot before the status shows which slot boots next and whether it is
    marked good.
- If the SSH connection drops during the restore, the kit asks the unit for the outcome itself. When it cannot, it
  prints the command to ask later, `ssh root@192.168.1.1 air6-stock result DIR` (with the directory it printed).

While a backup or a restore runs, `set-active` is refused ("an update of the other slot is in progress"). If one was
interrupted, `set-active`, `stock-backup` and `restore-stock` stay refused until the next reboot.

### OpenWrt starts but you cannot reach it

**A trial image that is not kept:** wait. If its timer was armed, it returns to the other slot about 10 minutes
after start-up. Whether the timer was armed cannot be checked when you cannot reach the unit; if nothing happens
within 15 minutes, use one of the ways below.

**Its settings are the problem: failsafe mode.** Failsafe mode starts OpenWrt without your settings, at 192.168.1.1
on jack 1, with no password.

1. Unplug the power and plug it back in.
2. Press the WPS key on the back slowly, about once a second (hold each press for a moment), for about 30 seconds.
   OpenWrt waits for a key for 4 seconds early in start-up, about 15-20 seconds after the power is plugged in; one
   press inside that wait is enough. Quick taps can be missed.
3. Log in with `ssh root@192.168.1.1` from the computer on jack 1, fix or reset the settings (OpenWrt's
   [failsafe guide](https://openwrt.org/docs/guide-user/troubleshooting/failsafe_and_factory_reset)), and leave
   failsafe mode with `reboot -f`.

Use WPS rather than RESET: a RESET press that misses the wait reaches normal OpenWrt, where a short press reboots and
a press of 5 seconds or more erases your settings. Use WPS for failsafe mode; the front LEVEL key is for switching
slots.

Tried on one unit: failsafe mode entered with WPS and with RESET, 192.168.1.1 set on jack 1, left with `reboot -f`
over the serial console. Logging in over the network was not tried.

**The build itself does not work: switch slots with the LEVEL key.** Unplug the power, hold the front LEVEL key, and
plug the power back in while holding it. Keep holding: the blue LEDs start the countdown about 15-20 seconds after
the power is plugged in.

| What you see | What it means | What to do |
| --- | --- | --- |
| The three blue signal LEDs light up and go out one by one (3 seconds) | Counting down | Keep holding; release now to cancel |
| The blue LEDs blink | The other slot is selected | Release the key: the unit reboots into the other slot |
| The red signal LED blinks | The switch was refused before anything was written (usually: the other slot is not marked good) | Release the key: the unit starts normally |
| The red signal LED stays on | Something did not go as planned: the selection could not be written, the reboot failed, or the key was held too long; the next boot slot may be either one (the serial console says which) | Release the key; once the unit is up, check `air6-slot status` |
| You hold the key for more than a minute after the count | The switch is undone where possible; red LED on (the serial console says if the undo was refused or failed) | Release the key |

The switch and the cancel were tried on one unit; the red-LED and one-minute cases were not.

## Technical notes

- The boot control bytes (`bootctrl=`) are 10 bytes in the `misc` partition: slot A priority, retry count, success
  flag, update type, one unused byte, then the same for slot B. The slot with priority `0f` boots. Before an install
  from slot A they read for example `0f000101000e00010100` (A preferred and successful). After the install they read
  `0e000101000f02000100` (B preferred, retry 02, not yet successful); from slot B, `0f020001000e00010100`.
- The install uses the stock firmware's own script (`/lib/upgrade/bootctrl.sh`, `change_slot_info`) and sets the
  new slot's retry count to 02. The bootloader increments it at every warm boot of that slot and switches to the
  other slot when it reads 4: right after an install or update, OpenWrt boots twice (retry 3 and 4) and the third
  boot goes to the other slot, unless a finished start-up has marked the slot good in between.
- The same image works in either slot: the bootloader replaces `root=/dev/mmcblk0p24` on the kernel command line with
  the booted slot's root partition (p26 on slot A, p39 on slot B), and `CHECK.txt` checks that the image has this
  value. OpenWrt in slot A has run after an update; an install into slot A from the stock firmware (a unit whose
  stock firmware runs from slot B) has not been tried.
- `./device.sh status root@192.168.1.1` on OpenWrt runs `air6-slot status`. It shows the same bytes per slot, the
  root file system check, whether the image is a trial image, any slot that reached the bootloader's retry limit while
  it was not marked good (kept in `/etc/air6-slot/failed-events`; an uncommitted trial image that is rebooted twice
  leaves the same record) and the last sysupgrade record.
- At the end of each start-up, OpenWrt also resets the other slot's retry count when it is above 3; otherwise the
  bootloader would refuse to switch to that slot later.
- What the image check (`out/$STAMP/CHECK.txt`) covers: see [docs/build.md](build.md#what-a-build-leaves-behind).
  It cannot prove that an image boots.
