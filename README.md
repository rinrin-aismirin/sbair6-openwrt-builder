# sbair6-openwrt-builder: OpenWrt for the SoftBank Air 6

> [!CAUTION]
> **USE AT YOUR OWN RISK.**
>
> This is an unofficial, early port. It is not supported by SoftBank or by the OpenWrt project, and nobody
> guarantees support for it. Installing it writes to the unit's internal storage. A mistake, a bug or a power cut at
> the wrong moment can leave the unit unusable, and there is no tested way to recover it without the stock firmware.
>
> The Wi-Fi radio is driven by OpenWrt (the mt76 driver), not by the stock software it was certified with. Wi-Fi is
> off after installation. As the OpenWrt documentation puts it, "OpenWrt is free software, but not free as in 'free
> of responsibilities'." If you turn Wi-Fi on, you are responsible for operating the unit in conformance with your
> country's regulations
> ([Country code for Wi-Fi operation](https://openwrt.org/docs/guide-user/network/wifi/wifi_countrycode)).

This page says what the kit is, what works, and how you use it. To try it, read the warning above, then
[What you need](#what-you-need) and the [quick start](#try-it-quick-start).

## What this is

The SoftBank Air 6 (model A775) is a 5G home router built on a MediaTek MT6990 module, with tri-band Wi-Fi 7 and two
Ethernet jacks. This kit builds an OpenWrt SNAPSHOT image for it (from OpenWrt's main branch, not a release) on your
Linux computer and installs it over SSH. The unit has two system slots, A and B: OpenWrt goes into the slot the stock
firmware is not running from, so the stock firmware stays as the way back until stage 2 ([below](#how-you-use-it)).
It is a work in progress, tested on one unit ([Status](#status)).

## What works and what does not

Works, tried on one unit:

- Both Ethernet jacks at 1 Gbit/s
- Wi-Fi 7 on 5 and 6 GHz together (MLO) with a Wi-Fi 7 phone; the 2.4 GHz band is present (not tried with a client)
- The USB 3 port (a memory stick at 5 Gbit/s)
- The front panel and jack LEDs
- Installing next to the stock firmware, and a trial image returning to it by itself about 10 minutes after start-up
- The bootloader returning to the other slot after failed starts
- Updates that keep your settings (`./device.sh upgrade`), in both directions between the slots
- A backup of the stock slot, and restoring the stock firmware from it after OpenWrt had overwritten that slot
- Switching slots with the LEVEL key, and entering failsafe mode with the WPS key (not reached from a computer); both
  last tried on 2026-10-28, before later changes to `air6-slot`, which the LEVEL key runs

Does not work, or not tried:

- The 5G/LTE modem is off in the default build: internet only through a cable on jack 2. An optional, experimental
  build includes it; it writes to partitions the stock firmware shares
  ([docs/features/modem.md](docs/features/modem.md))
- OpenWrt's network defaults (jack 1 = LAN at 192.168.1.1 with a DHCP server, jack 2 = WAN): not tried on a unit
- A normal image, or a kept trial image, that has finished starting does not return by itself, even if you cannot
  reach it: the ways out are manual ([when you cannot reach the unit](docs/recovery.md))
- A stock firmware update overwrites the OpenWrt slot (read from the stock update script; not observed)
- A unit on which neither slot starts: no supported or tested recovery (no serial-console procedure)
- Installing from a unit whose stock firmware runs from slot B: not tried
- Over-current protection on the USB port: not ported

## How you use it

1. **Try** ([docs/1-try.md](docs/1-try.md)): build a trial image and install it into the slot the stock firmware is
   not running from. The stock firmware stays in its slot as the way back.
2. **Keep** ([docs/2-keep.md](docs/2-keep.md)): back up the stock slot, then write the same build into it with
   `./device.sh upgrade` (tried on one unit with the current build). Both slots then hold OpenWrt; the
   stock firmware exists only as the backup file. Restoring it runs from OpenWrt: if neither slot starts, there is no
   tested way back.
3. **Update** ([docs/3-update.md](docs/3-update.md)): install later builds with `./device.sh upgrade`. Your settings
   are kept, and OpenWrt alternates between the two slots.
4. **Go back**, at any time ([docs/4-going-back.md](docs/4-going-back.md)): to the other slot, to the stock firmware
   (still in a slot, or restored from the backup), or into the same OpenWrt again.

## If you cannot reach the unit

When OpenWrt does not answer at 192.168.1.1 ([docs/recovery.md](docs/recovery.md)):

- [Check the connection](docs/recovery.md#check-the-connection-first): jack 1, the address, an old host key.
- [A trial image: wait](docs/recovery.md#a-trial-image-that-is-not-kept-wait): it returns if its timer was armed.
- [Failsafe mode with the WPS key](docs/recovery.md#its-settings-are-the-problem-failsafe-mode-with-the-wps-key)
- [Switch slots with the LEVEL key](docs/recovery.md#the-build-itself-does-not-work-switch-slots-with-the-level-key)

## Try it: quick start

The commands of stage 1. `root@DEVICE` is the unit while it runs the stock firmware (its address on your network,
reachable with root SSH); `root@192.168.1.1` is the unit while it runs OpenWrt, reached from the kit computer on
jack 1. Each step links to [docs/1-try.md](docs/1-try.md), which says what you should see and what to do otherwise.

**1. Prepare the build** ([details](docs/1-try.md#1-prepare-the-build))

If your Docker runs under a context other than the current one (for example rootless Docker), run
`export DOCKER_CONTEXT=rootless` first.

    git clone https://github.com/rinrin-aismirin/sbair6-openwrt-builder.git
    cd sbair6-openwrt-builder           # run all later commands here
    ./build.sh image                    # the Docker image the build runs in (once)
    ./build.sh fetch                    # ends with "openwrt/ at <commit>"
    ./build.sh pull-fw root@DEVICE      # the Wi-Fi firmware of your unit (once): four "local/firmware/..." lines

Stop on an error, an `abort:` line or an ssh error. A `warning:` about a hash from `pull-fw` means another stock
firmware version: accepted, but not tested. Your SSH key and settings, if you want them in the image, go into
`local/files/` now.

**2. Build** ([details](docs/1-try.md#2-build))

    STAMP=$(./build.sh start --trial)
    echo $STAMP                         # the build ID, for example 20261031-192819-083d5306: note it
    ./build.sh status $STAMP            # repeat until "result: done; next: ./build.sh collect ..."
    ./build.sh collect $STAMP           # copies the build to out/$STAMP/ and prints "RESULT: PASS"

Stop if `echo` prints an empty line (no build was started: read the message above it), or if `status` says
`result: failed` or `result: stopped without DONE or FAILED`
([The build fails](docs/troubleshooting.md#the-build-fails)). In a new shell, set `STAMP=` to the build ID again.

**3. Install** ([details](docs/1-try.md#3-install))

    grep 'boot.img policy' out/$STAMP/CHECK.txt   # "OK   boot.img policy trial (as built)"

Stop here if it says `policy normal`, prints nothing or an error: check `$STAMP`, or build again with `--trial`.

    ./device.sh status root@DEVICE                # first line bootslot=a: OpenWrt goes into slot B
    ./device.sh install root@DEVICE $STAMP        # ends with "installed; next: ./device.sh reboot root@DEVICE"

Stop if `install` ends any other way: do not reboot
([The install stops](docs/troubleshooting.md#the-install-stops)). `bootslot=b` (OpenWrt into slot A) is accepted but
has not been tried. Keep `out/$STAMP/`: stage 2 needs it.

**4. Reboot and connect** ([details](docs/1-try.md#4-reboot-and-connect))

Plug the kit computer into jack 1 first; with OpenWrt's defaults it should get an address in 192.168.1.0/24.

    ssh-keygen -R 192.168.1.1                     # forget an old host key for 192.168.1.1: OpenWrt has new keys
    ./device.sh reboot root@DEVICE                # "rebooting"; keep it (step 6) within 10 minutes of the reboot
    ./device.sh status root@192.168.1.1           # after about 70 s: policy=trial, timer=armed, root=rootfs_b

Without your key in the image, log in once with `ssh root@192.168.1.1` (no password) and set one with `passwd`.
Stop and read [step 4](docs/1-try.md#4-reboot-and-connect) if:

- the status shows `WARNING: ...` instead of `root=rootfs_b`: do not keep this image; let the timer return the unit;
- `timer=` shows `none`, `no-fallback`, `not-armed`, `error` or `overdue`: the unit will not return by itself;
- the unit comes back with the stock firmware, or neither 192.168.1.1 nor the stock firmware answers after 15 minutes
  ([when you cannot reach the unit](docs/recovery.md)).

**5. Check that it works** ([details](docs/1-try.md#5-check-that-it-works))

Plug the internet connection into jack 2, then:

    ssh root@192.168.1.1 cat /tmp/sysinfo/board_name    # softbank,air6
    ssh root@192.168.1.1 ip -4 addr show wan             # an address
    ssh root@192.168.1.1 ping -c 3 openwrt.org           # three answers

Another board name: do not keep the image. No address or no answers: the image may still be fine, since OpenWrt's
network defaults have not been tried on a unit; read [step 5](docs/1-try.md#5-check-that-it-works) before you keep it.

**6. Keep the trial image** ([details](docs/1-try.md#6-keep-the-trial-image))

Only if you want to keep it, and within 10 minutes of the reboot:

    ./device.sh trial-commit root@192.168.1.1     # "slot b committed (...)"; an "error:" line: it was not kept

If you do not run it and the status showed `timer=armed`, the unit returns to the stock firmware by itself; the stock
firmware and its slot are unchanged. What comes after this stage: [docs/1-try.md](docs/1-try.md#next).

## What you need

- A Linux computer with Docker and git, and about 20 GB of free disk space (measured: build cache 13 GB, Docker
  image 1.2 GB, OpenWrt source 0.4 GB). Tested on x86_64 Debian 13 with rootless Docker; other setups have not been
  tried. The docs call it "the kit computer".
- The Air 6, running the stock firmware, and root SSH access to it. This kit does not set up that access.
- A computer you can plug into jack 1 of the Air 6, to reach OpenWrt after the install. The kit computer is the
  simplest choice: `./device.sh` commands for a unit running OpenWrt need it on jack 1, and updates (stages 2 and 3)
  work only from it.

## Status

Tested on one unit, in short tests (hours, not days). The tested images used a local overlay that set the unit up as
an access point on an existing network, so OpenWrt's own network defaults have not been tried. Nothing has run for
days.

What was tested, what was not, and what is not supported, area by area:
[docs/reference/status.md](docs/reference/status.md).

## Documentation

| Page | What it is for |
| --- | --- |
| [docs/1-try.md](docs/1-try.md) | Stage 1: build a trial image, install it next to the stock firmware, check it, keep it |
| [docs/2-keep.md](docs/2-keep.md) | Stage 2: back up the stock slot, then write the same build into it |
| [docs/3-update.md](docs/3-update.md) | Stage 3: install a later build with `./device.sh upgrade`, keeping your settings |
| [docs/4-going-back.md](docs/4-going-back.md) | Stage 4: the other slot, the stock firmware, or the same OpenWrt again |
| [docs/recovery.md](docs/recovery.md) | When you cannot reach the unit: the connection, waiting for a trial image, failsafe mode, the LEVEL key |
| [docs/troubleshooting.md](docs/troubleshooting.md) | One section per symptom: build, install, sysupgrade, `upgrade-check`, stock restore, `set-active` or `switch` |
| [docs/build.md](docs/build.md) | Your SSH key and settings in the image, build options, packages, what a build leaves behind |
| [docs/features/modem.md](docs/features/modem.md) | The 5G/LTE modem (optional, experimental) |
| [docs/features/usb-nic.md](docs/features/usb-nic.md) | A USB 2.5G network adapter (RTL8156B; optional, experimental) |
| [docs/reference/README.md](docs/reference/README.md) | Technical reference: the two slots, the bootloader, the success flag, the ways out; list of pages |
| [docs/reference/status.md](docs/reference/status.md) | What has been tried on a unit, what has not, what is not supported |
| [docs/reference/boot-control.md](docs/reference/boot-control.md) | How the unit chooses the slot it boots, marking a slot good, trial images, `air6-slot` |
| [docs/reference/keys-and-failsafe.md](docs/reference/keys-and-failsafe.md) | The RESET, WPS and LEVEL keys: failsafe mode, switching slots |
| [docs/reference/sysupgrade.md](docs/reference/sysupgrade.md) | Updates from OpenWrt: the package, the checks, the write, the result record |
| [docs/reference/stock-backup.md](docs/reference/stock-backup.md) | The stock slot backup: what is saved, how it is checked and confirmed, the restore |
| [docs/reference/partitions.md](docs/reference/partitions.md) | The eMMC partitions, which belong to a slot, which tool writes which |
| [docs/reference/hardware.md](docs/reference/hardware.md) | The parts of the Air 6 the OpenWrt port drives, and how they are set up |

## What it is based on

- **OpenWrt:** a fork of OpenWrt main with the MT6990 platform and the Air 6 added,
  https://github.com/rinrin-aismirin/openwrt (branch `air6`). The kernel support comes from an OpenWrt tree for
  another MT6990 board, the FiberHome LG6851F: https://github.com/13179415360/openwrt-mt6990-lg6851f.
- **Wi-Fi firmware:** copied over SSH from the stock firmware of your own unit.
- **Boot image tools:** the boot image packer and the signing tool with the MT6990 SDK test keys, which the stock
  bootloader accepts, are downloaded from the LG6851F repository when you build.

The files from the stock firmware and from the LG6851F repository are not part of this repository: we have not found
a licence that allows redistributing them. The kit fetches them itself and checks them by hash: a boot image tool
with another hash stops the build; Wi-Fi firmware with another hash is accepted with a warning, but has not been
tested ([docs/build.md](docs/build.md#files-from-outside-this-repository)).
