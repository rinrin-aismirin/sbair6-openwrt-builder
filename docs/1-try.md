# Stage 1: try OpenWrt next to the stock firmware

This page builds a trial image, installs it into the slot the stock firmware is not running from, and checks it. Read
the warning at the top of the [README](../README.md) first. The commands are the same as in the README's
[quick start](../README.md#try-it-quick-start); this page adds what you see, why, and what to do otherwise.

## Before you start

You need:

- The kit computer: Linux with Docker and git, and about 20 GB of free disk space
  ([details](../README.md#what-you-need)).
- The Air 6, running the stock firmware, and root SSH access to it. This kit does not set up that access.
- A computer you can plug into jack 1 of the Air 6. The kit computer is the simplest choice.

What this stage changes on the unit:

- The install writes the boot and root partitions of the slot the stock firmware is not running from, and tells the
  bootloader to try that slot next. It never writes the stock firmware's slot.
- This stage always uses a trial image. A trial image is not marked good (`success=01`) at the end of start-up.
  Instead it arms a timer early in start-up: unless you keep the image (step 6), the timer switches back to the
  other slot about 10 minutes after start-up and reboots. The timer is armed only when the other slot is marked
  good; the stock firmware's slot is, after a normal start of the stock firmware. How it works:
  [docs/reference/boot-control.md](reference/boot-control.md).

The ways back during this stage, in short (all of them: [docs/reference/README.md](reference/README.md#overview)):

- The trial image is not kept: the timer returns the unit to the stock firmware.
- OpenWrt crashes and the unit resets before start-up finishes: the bootloader returns to the stock firmware after
  a few failed attempts (in the one crash test, about 2 minutes in all; a crash right after an install has not been
  tried; [details](reference/boot-control.md#how-the-bootloader-uses-them)). Pulling the power does not count as an
  attempt.
- OpenWrt starts but cannot be reached: [docs/recovery.md](recovery.md) (the connection, waiting, failsafe mode, the
  LEVEL key).
- None: an image that hangs before start-up finishes without the unit resetting has no automatic way back, and
  pulling the power does not bring the other slot back.

In the commands, `root@DEVICE` is the unit while it runs the stock firmware (its address on your network, reachable
with root SSH), and `root@192.168.1.1` is the unit while it runs OpenWrt, from a computer on jack 1.
`./device.sh ... root@192.168.1.1` therefore needs the kit computer on jack 1; from another computer on jack 1, run the
`air6-slot` command shown next to it. `$STAMP` is the build ID, the name of a directory under `out/`.

## 1. Prepare the build

Get the kit and run all later commands in its directory:

    git clone https://github.com/rinrin-aismirin/sbair6-openwrt-builder.git
    cd sbair6-openwrt-builder

If your Docker runs under a context other than the current one (for example rootless Docker), set it first:

    export DOCKER_CONTEXT=rootless

Build the Docker image the build runs in (once). If it ends with an error, stop and fix Docker first.

    ./build.sh image

Get the OpenWrt fork, at the commit pinned in `fork.lock`. It ends with `openwrt/ at <commit>`; on an error
(`fetch: wrong commit`, a git error), stop.

    ./build.sh fetch

Copy the Wi-Fi firmware from your unit (once; the unit must run the stock firmware):

    ./build.sh pull-fw root@DEVICE

It prints four lines `local/firmware/mt7996/<file> <- <path on the unit>`. An `abort: ...` line (for example `abort: not
the stock firmware`) or an ssh error: stop, the files were not copied. A `warning: ... has sha256 ..., not the one in
stock-firmware.lock` means your unit has another stock firmware version than the ones the kit lists. The file is used,
but that version has not been tested ([details](build.md#files-from-outside-this-repository)).

Before you build, decide what goes into the image. It cannot be added to an image that is already built.

- **Your SSH key and settings.** Files under `local/files/` go into the image, for example your public key in
  `local/files/etc/dropbear/authorized_keys`. Without a key, the first login is as root with no password (OpenWrt's
  default); once you set a password, every `./device.sh` command for OpenWrt asks for it, some of them twice. Details
  and file permissions: [docs/build.md](build.md#customizing-the-image).
- **Optional features.** The modem needs files from your unit before the build
  ([docs/features/modem.md](features/modem.md)). A USB 2.5G adapter needs a build option
  ([docs/features/usb-nic.md](features/usb-nic.md)). What they add to the build command goes into the `start`
  command of step 2.

## 2. Build

Start a trial build and note its build ID:

    STAMP=$(./build.sh start --trial)
    echo $STAMP

`echo` prints the build ID, for example `20261031-192819-083d5306`. `start` also reminds you not to change the kit,
`local/` or the fork checkout until the build is done or failed: the build reads them while it runs. In a new
shell, set the build ID again before using it: `STAMP=20261031-192819-083d5306`.

If `echo` prints an empty line, `start` did not start a build: read the message it printed above (for example
`Wi-Fi firmware missing`, `openwrt/ not found`, `volume ... is in use`) and stop.

Follow the build:

    ./build.sh status $STAMP

Repeat it until the last line says `result: done; next: ./build.sh collect ...`. A full build took about 15 minutes
on a 32-thread machine, including the downloads. If the last line says `result: failed` or
`result: stopped without DONE or FAILED`, stop: [The build fails](troubleshooting.md#the-build-fails).

Copy the result to `out/$STAMP/`:

    ./build.sh collect $STAMP

It prints the last line of the image check, `RESULT: PASS`. The check is in `out/$STAMP/CHECK.txt`, one line per
check; what it covers: [docs/build.md](build.md#what-a-build-leaves-behind). The check runs at the end of the build:
when it fails, the build fails (`status` says `result: failed`), and `collect` refuses it as not done. The failed
checks are then in the logs: [The build fails](troubleshooting.md#the-build-fails).

## 3. Install

Check that the build is a trial image:

    grep 'boot.img policy' out/$STAMP/CHECK.txt

It must say `OK   boot.img policy trial (as built)`. `policy normal` means `start` ran without `--trial`: build
again as in step 2.

Look at the unit:

    ./device.sh status root@DEVICE

On the stock firmware, the first line shows the running slot and the boot control bytes, for example:

    00:03:51 bootslot=a uptime=959.17 bootctrl=0f000101000e00010100

`bootslot=a` means the stock firmware runs from slot A, so OpenWrt will go into slot B. With `bootslot=b`, OpenWrt
goes into slot A; the install accepts it, but it has not been tried. The bytes:
[docs/reference/boot-control.md](reference/boot-control.md).

Install:

    ./device.sh install root@DEVICE $STAMP

This uploads the two image files (160 MiB) and writes them into the other slot. It does not reboot. When it worked,
the output ends with:

    boot_b and rootfs_b written and verified
    ...
    slot b preferred, retry preset 02
    installed; next: ./device.sh reboot root@DEVICE

(`slot a` instead of `slot b` if the stock firmware runs from slot B.) **If it ends any other way, do not reboot**:
[The install stops](troubleshooting.md#the-install-stops).

Keep `out/$STAMP/`: booting this build again later, and stage 2, need it.

## 4. Reboot and connect

Before rebooting:

- Plug a computer into jack 1. With OpenWrt's defaults it should get an address in 192.168.1.0/24 (these defaults
  have not been tried on a unit yet). If that computer is also connected to another network that uses
  192.168.1.0/24, disconnect it.
- OpenWrt has new SSH host keys. Remove an old entry for 192.168.1.1 from that computer, so ssh does not refuse later:

      ssh-keygen -R 192.168.1.1

Then reboot. If you want to keep the image, keep it within 10 minutes of this reboot
([step 6](#6-keep-the-trial-image)).

    ./device.sh reboot root@DEVICE

It prints `rebooting`. OpenWrt took about 70 seconds to answer in our tests. Log in with `ssh root@192.168.1.1` or
open LuCI at http://192.168.1.1. Without a key in the image, root has no password: set one with `passwd`.

Look at the slots (from another computer: `ssh root@192.168.1.1 air6-slot status`):

    ./device.sh status root@192.168.1.1

The output starts like this (here OpenWrt runs from slot B):

    booted=b
    next=b
    slot a: prio=0e retry=00 success=01 uptype=01
    slot b: prio=0f retry=03 success=00 uptype=01
    root=rootfs_b
    policy=trial
    timer=armed, returns to slot a in 574s unless 'air6-slot trial commit'

- `policy=trial`: the image is a trial image. Its slot stays `success=00` until you keep it.
- `timer=armed, returns to slot a in ...s`: the timer runs. `timer=none`, `no-fallback`, `not-armed`, `error` or
  `overdue`: no return by itself ([step 6](#6-keep-the-trial-image)).
- `WARNING: ...` instead of `root=rootfs_b`: the image runs on another slot's root file system. Do not keep it (no
  `trial-commit`); let the timer return the unit to the stock firmware.

If 192.168.1.1 does not answer and the unit answers at `root@DEVICE` with the stock firmware instead, OpenWrt did not
start (or was not kept in time). The stock firmware and its slot are unchanged. You can start the same build again
([Boot the same OpenWrt again](4-going-back.md#boot-the-same-openwrt-again)) or install again from step 3.

How long to wait: OpenWrt answered after about 70 seconds in our tests. A start that fails before start-up finishes
is retried a few times before the bootloader returns to the stock firmware ([Before you start](#before-you-start)),
and a trial image that cannot be reached returns about 10 minutes after start-up when its timer is armed. If neither
192.168.1.1 nor the stock firmware answers after 15 minutes:
[docs/recovery.md](recovery.md).

## 5. Check that it works

From the computer on jack 1:

    ssh root@192.168.1.1 cat /tmp/sysinfo/board_name

It says `softbank,air6`. If it says anything else, the unit does not run this image: do not keep it.

Plug the internet connection into jack 2 (WAN), then:

    ssh root@192.168.1.1 ip -4 addr show wan
    ssh root@192.168.1.1 ping -c 3 openwrt.org

The first shows an address, the second three answers. This is expected with OpenWrt's defaults, but has not yet been
seen on a unit. No address or no answers: the image may still be fine, since OpenWrt's network defaults have not been
tried. Keep it (step 6) only if you can reach it from jack 1 and want to look further; otherwise do nothing and let
the timer return the unit to the stock firmware.

For a closer look, optional, after `ssh root@192.168.1.1`:

- Plug in a USB memory stick. `dmesg | tail` shows it, and `ls /dev/sd*` lists the disk and its partitions.
- `dmesg | grep mt7996e` shows the Wi-Fi firmware build times. With the firmware listed in `stock-firmware.lock`
  they are: ROM patch `20230704161925a`, WM `20240315201529`, DSP `20231113135337`, WA `20240315201449`. If your
  firmware had another hash (`pull-fw` warned about it), other times are expected; check `out/$STAMP/PROVENANCE`.
  There must be no `eeprom load fail`, `no valid board EEPROM` or `timeout` lines.
- `dmesg | grep "PCS detected"` shows two lines: the Ethernet links to the switch were found.

Wi-Fi is off until you turn it on in LuCI or with `uci`. Read the warning in the README first.

## 6. Keep the trial image

Only when you want to keep the image after the checks above, and within 10 minutes of the reboot:

    ./device.sh trial-commit root@192.168.1.1

(From another computer: `ssh root@192.168.1.1 air6-slot trial commit`.) The output shows `slot b committed (bootctrl
... -> ...)` (or `slot a`). The slot is now marked good, and the image behaves like a normal image: it marks its slot
good again at every start-up that finishes, and stays across reboots. The stock firmware is still in the other slot.

An `error:` line means the image was not kept: `error: the trial timer already selected slot a` or
`error: slot b is no longer the next boot slot` (the unit returns, or has returned, to the stock firmware; start the
build again with [Boot the same OpenWrt again](4-going-back.md#boot-the-same-openwrt-again)), or
`error: not a trial image` (a normal image marks its slot good by itself).

If you do not keep it and the status shows `timer=armed`, the unit returns to the stock firmware about 10 minutes
after start-up. `timer=armed, due ...s ago` means the return is under way.

These `timer=` values mean that no return will happen by itself:

- `committed`: the image was kept.
- `cancelled`: a slot was chosen by hand (`set-active`), or at the deadline the slot was already marked good or no
  longer booted next.
- `none`, `no-fallback`, `not-armed`, `error`, `overdue`: keep the image, or
  [go back by hand](4-going-back.md#start-the-other-slot).

All values: [docs/reference/boot-control.md](reference/boot-control.md#trial-images).

Until the image is kept, the bootloader also counts its warm reboots (pulling the power does not count): after the
first start, one more warm reboot starts OpenWrt again, and the next one starts the stock firmware.

## Next

- **Keep OpenWrt for good:** [docs/2-keep.md](2-keep.md) backs up the stock slot, then writes the same trial build
  into it.
  `./device.sh upgrade` writes the stock firmware's slot: do not run it before reading that page.
- **Go back to the stock firmware:** [Start the other slot](4-going-back.md#start-the-other-slot). While the stock
  firmware runs, it may update itself, and its update overwrites the OpenWrt slot (read from the stock update
  script; not observed).
- **Optional features:** built with the modem, continue with [docs/features/modem.md](features/modem.md) (NV backup
  first); built with the USB adapter driver, check it as in [docs/features/usb-nic.md](features/usb-nic.md).
- **Settings and packages:** OpenWrt keeps its settings in its own slot. It does not use the stock firmware's data
  partition (`user_data`): do not format that partition, the stock firmware keeps its data there
  ([docs/reference/partitions.md](reference/partitions.md)). Packages you add with `apk` must come from the same
  build ([docs/build.md](build.md#what-a-build-leaves-behind)).
- **Something went wrong:** [docs/troubleshooting.md](troubleshooting.md).
