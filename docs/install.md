# Installing and removing OpenWrt

This page walks through one install from the start: choosing what to build, building, installing, the first login,
and later going back to the stock firmware or recovering. Read the warning at the top of the
[README](../README.md) first.

## How it works

The Air 6 has two system slots, A and B. The stock firmware runs from one of them. The install writes OpenWrt into
the other slot and tells the bootloader to try it next. The stock firmware's slot is never written, so it stays as
the way back.

When a normal image finishes starting, it marks its slot as good (`success=01` in the status; the tools call it
"successful"), and the bootloader keeps booting it from then on. "Good" only means that start-up finished: it does
not check that the network works.

Ways out when an install goes wrong:

| Situation | Way out | Ends in | Tried on one unit |
| --- | --- | --- | --- |
| OpenWrt crashes or hangs, and the unit resets before start-up finishes | Automatic: right after an install the bootloader gives up after two attempts (about 2 minutes each) | The stock firmware | Yes |
| A trial image (see [step 1](#1-choose-what-to-build)) is not kept | Automatic: 10 minutes after start-up, when its return timer is armed | The stock firmware | Yes (on an earlier build) |
| OpenWrt starts, but its settings make it unreachable | Failsafe mode with the WPS key ([below](#openwrt-starts-but-you-cannot-reach-it)) | The same OpenWrt, without your settings | Yes (entered; not reached from a computer) |
| OpenWrt starts, but the build itself does not work | Hold the LEVEL key at power-on ([below](#openwrt-starts-but-you-cannot-reach-it)) | The stock firmware | Yes |

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
  switches back to the stock firmware 10 minutes later and reboots. The timer is only armed when the stock
  firmware's slot is marked good (it is after a normal stock boot). A normal image marks its slot as good as soon as
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
    policy=normal

- Normal image (`policy=normal`): the line of the slot it runs from (`booted=`) shows `success=01` once start-up has
  finished.
- Trial image (`policy=trial`): that slot stays `success=00`, and `timer=armed, returns to slot ... in ...s` shows
  that the return timer runs. See [step 6](#6-trial-image-keep-it) for the other `timer=` values.

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

If you do nothing and the status shows `timer=armed`, the unit returns to the stock firmware 10 minutes after
start-up (`timer=armed, due ...s ago` means the return is under way). Other `timer=` values:

| Value | Meaning |
| --- | --- |
| `committed` | Kept; no return |
| `cancelled` | A slot was chosen by hand (`set-active`); no return |
| `fired` | The stock firmware's slot is already selected; a reboot follows |
| `none`, `no-fallback`, `not-armed`, `error`, `overdue` | No return will happen by itself; keep the image or [go back by hand](#going-back-to-the-stock-firmware) |

## Optional features after the install

With either image: built with the modem, continue with [docs/modem.md](modem.md) (NV backup first); built with the
USB adapter driver, check it as in [docs/usb-nic.md](usb-nic.md).

## Across reboots

A normal image marks its slot as good again at every boot that finishes starting. A kept trial image does the same.
Until a trial image is kept, the bootloader also counts its warm reboots (pulling the power does not count): right
after an install, one more reboot starts OpenWrt again and the one after that starts the stock firmware.

## Settings and packages

OpenWrt keeps its settings in its own slot (about 120 MiB). It does not use the stock firmware's data partition
(`user_data`, about 3 GiB): do not format that partition, the stock firmware keeps its data there.

Packages you add with `apk` must come from the build whose image the unit runs; see
[docs/build.md](build.md#what-a-build-leaves-behind).

## Going back to the stock firmware

`./device.sh status root@192.168.1.1` shows which slot OpenWrt runs from (`booted=`); the stock firmware is in the
other one. For example, with OpenWrt in slot B:

    ./device.sh set-active root@192.168.1.1 a
    ./device.sh reboot root@192.168.1.1

(From another computer: `ssh root@192.168.1.1 air6-slot set-active a`, then `ssh root@192.168.1.1 reboot`.)

The unit reboots into the stock firmware. OpenWrt stays in its slot. `set-active` refuses a slot that is not marked
good ("not marked successful").

While the stock firmware runs, it may update itself, and an update overwrites the OpenWrt slot (see the README).

A unit that runs an image built with an earlier version of this kit has `air6-abguard` instead of `air6-slot`, and
the current `device.sh` refuses it. Go back with `ssh root@192.168.1.1 air6-abguard revert` and
`ssh root@192.168.1.1 reboot` (what the earlier kit's `to-stock` did), then install a new build.

## Booting the same OpenWrt again

From the stock firmware, without installing again:

    ./device.sh switch root@DEVICE $STAMP
    ./device.sh reboot root@DEVICE

`switch` checks that the boot partition of the OpenWrt slot matches `out/$STAMP/boot.img`; it does not check the
rest of the slot. The slot starts like a fresh install (a trial image arms its timer again). Continue as in step 4.

## Updating to a new build

There is no in-place update. Note or back up your settings, go back to the stock firmware, then install the new
build (steps 3 to 6). The install replaces the whole OpenWrt slot, so your OpenWrt settings and added packages are
lost.

## When something goes wrong

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

### OpenWrt starts but you cannot reach it

**A trial image that is not kept:** wait. If its timer was armed, it returns to the stock firmware about 10 minutes
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
  other slot when it reads 4: right after an install, OpenWrt boots twice (retry 3 and 4) and the third boot goes to
  the stock firmware, unless a finished start-up has marked the slot good in between.
- The same image works in either slot: the bootloader replaces `root=` on the kernel command line with the booted
  slot's root partition. Installing into slot A (from a unit whose stock firmware runs from slot B) has not been
  tested yet.
- `./device.sh status root@192.168.1.1` on OpenWrt runs `air6-slot status`. It shows the same bytes per slot, whether
  the image is a trial image, and any slot that reached the bootloader's retry limit while it was not marked good
  (kept in `/etc/air6-slot/failed-events`; an uncommitted trial image leaves the same record).
- At the end of each start-up, OpenWrt also resets the other slot's retry count when it is above 3; otherwise the
  bootloader would refuse to switch to that slot later.
- What the image check (`out/$STAMP/CHECK.txt`) covers: see [docs/build.md](build.md#what-a-build-leaves-behind).
  It cannot prove that an image boots.
