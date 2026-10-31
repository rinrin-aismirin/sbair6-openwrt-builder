# Updating to a new build

This page is stage 3: installing a later build with `./device.sh upgrade` while OpenWrt runs. Each update writes the
slot OpenWrt is not running from, so OpenWrt alternates between slot A and slot B. Finish [Keep](2-keep.md) first:
while the other slot still holds the stock firmware, an update is that stage.

Run the commands on the kit computer, plugged into jack 1 of the unit. `root@192.168.1.1` is the unit while it runs
OpenWrt; `$STAMP` is the build ID of the new build (a directory under `out/`). In a new shell, set it again, for
example `STAMP=20261031-192819-083d5306`.

## Before you update

- **The kit computer on jack 1.** `upgrade` and `upgrade-check` do not work from another computer: `upgrade-check`
  reads the request that `upgrade` records in `out/$STAMP/`.
- **A new build from this kit.** For a newer kit, run in the kit directory:

      git pull
      ./build.sh image      # rebuilds the Docker image the build runs in; fast when nothing changed
      ./build.sh fetch      # the OpenWrt fork at the commit in the new fork.lock

  Then build as in [Try, step 2](1-try.md#2-build): `./build.sh start --trial` for a build that has not run on your
  unit before (recommended), `./build.sh start` for a normal image, then `status` and `collect`. This sequence follows
  from the scripts; it has not been tried as a whole. `out/$STAMP/CHECK.txt` must end with `RESULT: PASS`, and
  `out/$STAMP/sysupgrade.bin` must exist (kits from this version on make it).
- **An image on the unit with sysupgrade support.** `ssh root@192.168.1.1 ls /lib/air6/upgrade.sh` must list the
  file. If it fails, see
  [Units with an image from an earlier kit](4-going-back.md#units-with-an-image-from-an-earlier-kit).
- **The running slot is marked good and boots next.** In `./device.sh status root@192.168.1.1`, the line of the booted
  slot (`booted=`) shows `success=01`, `next=` names the same slot, and the status shows `root=rootfs_` with that
  slot's letter (not `WARNING: ...`). A trial image must be kept first ([Try, step 6](1-try.md#6-keep-the-trial-image)).
- **A build with the modem** must match the modem firmware of the slot it goes into
  ([Updating with the modem](features/modem.md#updating-with-the-modem)).

### What the update carries over

- **Settings:** what OpenWrt's sysupgrade keeps: `/etc/config`, the files listed in `/etc/sysupgrade.conf` and the
  configuration files of packages (`ssh root@192.168.1.1 sysupgrade -l` lists them), including the root password and
  the SSH host keys. Other files are not carried over.
- **Packages** you added with `apk` are not carried over. Put what you need into the new build; see
  [build.md](build.md#customizing-the-image).
- **A stock backup confirmation** (`/etc/air6-slot/stock-backup-<slot>`) is not carried over. It is only needed while
  a slot holds the stock firmware ([Keep, step 1](2-keep.md#1-back-up-the-stock-slot)).

To start the new slot without the current settings, add `--no-config` as the last option:
`./device.sh upgrade root@192.168.1.1 $STAMP --no-config`. The new slot then starts with the defaults built into that
image. Files and uci-defaults included through `local/files` still apply; where the image does not change them, that
means OpenWrt's default network, new SSH host keys (run `ssh-keygen -R 192.168.1.1` before connecting) and no root
password. `--no-config` has not been tried on a unit.

## Update

    ./device.sh upgrade root@192.168.1.1 $STAMP

It uploads `sysupgrade.bin`, lets the unit check it (`sysupgrade -T`), records the request in
`out/$STAMP/upgrade-request-<time>`, then starts sysupgrade. When the unit refuses, nothing is written and the output
ends with `the unit refused the package (see above); nothing was written`; see
[When the unit refuses](#when-the-unit-refuses). Otherwise it ends with:

    sysupgrade request sent (request recorded in out/20261031-192819-083d5306/upgrade-request-...). ...
    The unit stops its services, writes slot b and reboots into it (1 to 3 minutes).
    Then run: ./device.sh upgrade-check root@192.168.1.1 20261031-192819-083d5306
    If it does not come back and the power LED blinks red, see docs/troubleshooting.md (sysupgrade stopped).

The unit then stops its services, writes the build into the other slot, carries your settings over and reboots into
the new slot. Allow 1 to 3 minutes, and leave the power on: a power cut during an update has not been tried. If the
unit does not come back and the power LED blinks red, see [sysupgrade stopped](troubleshooting.md#sysupgrade-stopped).
How the update checks and writes the slot: [reference/sysupgrade.md](reference/sysupgrade.md).

### From LuCI instead

LuCI's "Flash new firmware image" runs the same sysupgrade with the same checks. Use it only between OpenWrt slots:
[Keep](2-keep.md) (writing the stock slot) uses `./device.sh`, because the stock backup is taken with the kit.

1. In LuCI (http://192.168.1.1), open System, Backup / Flash Firmware, and click "Flash new firmware image".
2. Choose `out/$STAMP/sysupgrade.bin` from the kit computer. Leave "Keep settings and retain the current
   configuration" checked, then confirm.
3. The unit writes the other slot and reboots into it (1 to 3 minutes; leave the power on). With a trial image, keep
   it within 10 minutes of the reboot ([With a trial image](#with-a-trial-image)); run `trial-commit` over ssh.

A refusal behaves as with `./device.sh upgrade`: nothing is written, and "Force upgrade" does not override it
([When the unit refuses](#when-the-unit-refuses)). `upgrade-check` does not work for a LuCI update (there is no
request record). Check the result with `ssh root@192.168.1.1 air6-slot status` instead: `booted=` and
`root=rootfs_` show the new slot, and under "last sysupgrade record" the line shows `state=written` and `to=` the new
slot. Tried once on one unit, from slot A to slot B (2026-11-01); a manual `sysupgrade` on the command line has not
been tried.

## Check the result

Once the unit answers again (if `upgrade-check` cannot connect yet, wait and run it again):

    ./device.sh upgrade-check root@192.168.1.1 $STAMP

It prints the status of the unit, then compares the unit's record of the update with the request (same unit boot, same
image) and the root file system with the booted slot. The last lines give the result:

| `upgrade-check` says | Meaning | Next |
| --- | --- | --- |
| `result: written, and the unit runs the new slot X on rootfs_X` | The update finished and the new slot started | A normal image is marked good once start-up has finished (`success=01` in the status). A trial image needs `trial-commit` within 10 minutes of the reboot ([below](#with-a-trial-image)) |
| `result: written (the write finished), but the unit runs the old slot X again` | The write finished, and the unit is back on the old slot. Why is not known from this alone (an uncommitted trial image, a switch back, or failed starts). Seeing this needs the record to survive the restarts, which has not been tried. The reason for the return is in the status ("failed updates", the timer), not in the record | Decide from the status and from what you did; `upgrade` again if you want the build (a trial image: keep it in time, [below](#with-a-trial-image)) |
| `result: refused` or `result: failed` | Nothing was activated; the old slot stays next. "refused": nothing was written. "failed": a write was started or may have been | [`refused` or `failed`](troubleshooting.md#result-refused-or-result-failed) |
| `result: UNKNOWN - the unit has no record of this request` | The result of this request is not known | [upgrade-check does not say written](troubleshooting.md#upgrade-check-does-not-say-written) |
| `result: MISMATCH`, `result: UNKNOWN - the record of this request is incomplete`, or `written, ... but its root file system is not rootfs_X` | Not an expected state | Do not run `upgrade` again; keep the output and check the status |

The unit records each step of the update; at the next start-up, the slot that starts keeps the record ("last
sysupgrade record" in the status). A power cut before that start-up (a cold boot) loses it. `no upgrade request
recorded for out/$STAMP` means `upgrade` was not run with this build ID.

Marked good only means that start-up finished ([details](reference/boot-control.md#marking-a-slot-good)); it does
not check that the network works. With a normal image, check that it works as in
[Try, step 5](1-try.md#5-check-that-it-works). Once the new slot is
marked good (a normal image that finished starting, or a trial image after `trial-commit`), both slots hold a good
OpenWrt build, and [starting the other slot](4-going-back.md#start-the-other-slot) starts the previous build again.

## With a trial image

A trial image returns to the other slot about 10 minutes after start-up, while the status shows `timer=armed`, unless
you keep it ([how it works](reference/boot-control.md#trial-images)).

1. The status printed by `upgrade-check` shows `policy=trial` and `timer=armed, returns to slot ... in ...s`. For other
   `timer=` values, see [Try, step 6](1-try.md#6-keep-the-trial-image).
2. Check that it works, as in [Try, step 5](1-try.md#5-check-that-it-works). Keeping marks the slot good, which only
   means that start-up finished.
3. Within 10 minutes of the reboot into the new slot (the `timer=` line shows the time left), keep it:

       ./device.sh trial-commit root@192.168.1.1

   The output shows `slot a committed` (or `slot b`). From then on it behaves like a normal image.

If you do not keep it and the status shows `timer=armed`, the unit returns to the previous OpenWrt. The new slot
stays not marked good, and the next `upgrade` writes it again. In the two returns tried on a unit, `upgrade-check`
said UNKNOWN ([upgrade-check does not say written](troubleshooting.md#upgrade-check-does-not-say-written)).

Until a trial image is kept, the bootloader also counts its warm reboots (pulling the power does not count): right
after an update, one more reboot starts it again, and the one after that starts the other slot.

Tried on one unit: an uncommitted trial image returning by its timer, and by the bootloader after two warm reboots;
keeping a trial image after an update with `trial-commit` (2026-11-01).

## When the unit refuses

Nothing is written when an update is refused. None of these refusals can be overridden (`sysupgrade -F` included).

Refused by the unit (the output shows the unit's `error:` line, then `the unit refused the package (see above);
nothing was written`):

| The `error:` line says | Why | What to do |
| --- | --- | --- |
| `no confirmed backup of slot X`, `was not confirmed yet`, `verify slot X: FAILED`, `from another unit`, or another line from `air6-stock verify` (`is damaged`, `has another size than in the backup`) | The other slot holds the stock firmware, without a confirmed backup that still matches it | This is [Keep](2-keep.md): take a new backup ([step 1](2-keep.md#1-back-up-the-stock-slot)), then update again |
| `the booted slot X is not marked successful yet` | Start-up has not finished, or a trial image is not kept | Wait for start-up to finish, or run `./device.sh trial-commit root@192.168.1.1` |
| `the next boot slot is X, not the booted slot Y` | Another slot is already selected for the next boot (after `set-active` without a reboot, or a fired trial timer) | Reboot into the selected slot first, or select the booted slot again with `set-active` (it must be marked good) |
| `an update of the other slot is in progress` | A stock backup or restore is running | Wait until it ends. After an interrupted one, the refusal stays until the next reboot |
| `the running image boots the wrong rootfs`, `cannot tell which partition the root file system is on` | The root file system is not the booted slot's rootfs (`WARNING` in the status) | Do not update from this state; keep the output |
| `cannot tell what slot X holds`, `holds neither the stock firmware nor OpenWrt for the Air 6` | The other slot cannot be read, or holds something else | Keep the output and check the status |
| `the image's modem programs are ..., md1img_X is ...` | A build with the modem, for another modem firmware version than the other slot's | [Updating with the modem](features/modem.md#updating-with-the-modem) |
| Other lines about the package (`the package ...`, `CONTROL ...`, `kernel ...`, `root ...`) | The unit did not accept this `sysupgrade.bin` | Use a build from this kit whose `CHECK.txt` ends with `RESULT: PASS` |

Tried on one unit: the refusal for a missing backup (2026-10-31).

Refused by `device.sh` before anything is uploaded:

| `device.sh` says | What to do |
| --- | --- |
| `CHECK.txt not found` or `did not pass the image check` | Check the build ID; use a build that passed |
| `sysupgrade.bin not found (built by kits from this version on)` | Build again with this kit |
| `runs an image without sysupgrade support` or `runs an older OpenWrt image (air6-abguard)` | [Units with an image from an earlier kit](4-going-back.md#units-with-an-image-from-an-earlier-kit) |
| `is not running OpenWrt` | Check the address: the unit must run OpenWrt and answer at it |
| `upload damaged` | Run `upgrade` again |
| `upgrade: unknown option` | The only option is `--no-config`, as the last word |
