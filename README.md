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

## Overview

The SoftBank Air 6 (model A775) is a 5G home router built on a MediaTek MT6990 module, with tri-band Wi-Fi 7 and two
Ethernet jacks. This kit builds plain OpenWrt for it and installs it next to the stock firmware: the unit has two
system slots, and OpenWrt goes into the one the stock firmware is not running from. If OpenWrt crashes or cannot be
reached, the unit normally returns to the stock firmware by itself (see
[How it works](docs/install.md#how-it-works) for the one case it does not cover).

What it is based on:

- **OpenWrt:** a fork of OpenWrt main with the MT6990 platform and the Air 6 added,
  https://github.com/rinrin-aismirin/openwrt (branch `air6`). The kernel support comes from an OpenWrt tree for
  another MT6990 board, the FiberHome LG6851F: https://github.com/13179415360/openwrt-mt6990-lg6851f.
- **Wi-Fi firmware:** copied over SSH from the stock firmware of your own unit.
- **Boot image tools:** the boot image packer and the signing tool with the MT6990 SDK test keys, which the stock
  bootloader accepts, are downloaded from the LG6851F repository when you build.

The files from the stock firmware and from the LG6851F repository are not part of this repository: we have not found
a licence that allows redistributing them. The kit fetches them itself and checks them by hash (see
[Files from outside this repository](#files-from-outside-this-repository)).

What works today, in short tests on one unit (hours, not days):

- both Ethernet jacks (1 Gbit/s)
- Wi-Fi 7 on 5 GHz and 6 GHz, including MLO with a Wi-Fi 7 phone
- the USB 3 port (a memory stick at 5 Gbit/s)
- the front and jack LEDs
- returning to the stock firmware automatically when a new image does not come up

What does not work: the 5G/LTE modem (cellular support is not included), and updates that keep your settings.
Details are in [Status](#status).

## What you need

- A Linux computer with Docker and git, and about 20 GB of free disk space (measured: build cache 13 GB, Docker
  image 1.2 GB, OpenWrt source 0.4 GB). Tested on x86_64 Debian 13 with rootless Docker; other setups have not been
  tried.
- The Air 6, running the stock firmware, and root SSH access to it.
- A computer you can plug into jack 1 of the Air 6, to reach OpenWrt after the install. It can be the same Linux
  computer.

## Quick start

In the examples, `root@DEVICE` is the unit while it runs the stock firmware.

**0. Get the kit.** Run all later commands in this directory.

    git clone https://github.com/rinrin-aismirin/sbair6-openwrt-builder.git
    cd sbair6-openwrt-builder

If your Docker runs under a context other than the current one (for example rootless Docker), set it first:

    export DOCKER_CONTEXT=rootless

Optional: if you want your SSH key or your own settings in the image, put them under `local/files/` now (see
[Customizing the image](#customizing-the-image)). They cannot be added to an image that is already built.

**1. Build.** A full build took about 15 minutes on a 32-thread machine, including the downloads.

    ./build.sh image                   # the Docker image the build runs in (once)
    ./build.sh fetch                   # the OpenWrt fork, at the commit this kit is tested with
    ./build.sh pull-fw root@DEVICE     # the Wi-Fi firmware from your unit (once)
    STAMP=$(./build.sh start)          # start the build
    echo $STAMP                        # its build ID, for example 20261019-1200-8406013b; note it
    ./build.sh status $STAMP           # repeat until the last line says "result: done"
    ./build.sh collect $STAMP          # the result goes to out/$STAMP/; this must print "RESULT: PASS"

If `status` says `result: failed`, run `./build.sh logs $STAMP` and look at the log files it copies to
`out/logs-$STAMP/`.

In a new shell, set the build ID again before using it: `STAMP=20261019-1200-8406013b` (the directory name under
`out/`).

**2. Install.** The unit must run the stock firmware.

    ./device.sh install root@DEVICE $STAMP
    ./device.sh reboot root@DEVICE

**3. Confirm this boot.** Plug a computer into jack 1. OpenWrt's defaults give it an address in 192.168.1.0/24
(these defaults have not been tried on a unit yet; see [Status](#status)). Within 10 minutes of the reboot, run:

    ./device.sh confirm root@192.168.1.1

or, from a computer without this kit:

    ssh root@192.168.1.1 air6-abguard confirm

Without this, the unit goes back to the stock firmware after 10 minutes. That is on purpose: if you cannot reach
OpenWrt, you get the stock firmware back. On the first login, root has no password (OpenWrt's default); set one with
`passwd`.

`confirm` covers this boot only. When you have checked that OpenWrt works and want to keep it, see
[Keeping OpenWrt](docs/install.md#keeping-openwrt-across-reboots):

| Command | What it does |
| --- | --- |
| `./device.sh confirm` | stops the 10-minute return to the stock firmware, for this boot only |
| `air6-abguard commit` (on OpenWrt) | keeps OpenWrt: no more automatic return to the stock firmware |
| `./device.sh to-stock` | switches to the stock firmware now and reboots |

**To go back to the stock firmware** at any time:

    ./device.sh to-stock root@192.168.1.1

[docs/install.md](docs/install.md) explains each step, what you should see, and what to do when something goes
wrong.

## Status

### Tested

On one unit, in short tests:

- Boot, and the automatic return to the stock firmware (by the bootloader after failed boots, and by `air6-abguard`
  when OpenWrt is not confirmed).
- Ethernet: both jacks on the internal switch at 1 Gbit/s. Traffic in both directions and a cable replug, without
  errors.
- Wi-Fi with the stock Wi-Fi firmware: the 2.4, 5 and 6 GHz bands are present. One access point on 5 GHz and
  6 GHz together (MLO, WPA3) with a Wi-Fi 7 phone at 80 MHz: about 925 Mbit/s from the phone and 760-790 Mbit/s to
  the phone (iperf3).
- USB: a USB 3 memory stick (FAT) at 5 Gbit/s on the Type-A port.
- LEDs: front panel and jack LEDs.

The tested image used a local overlay to configure the unit as an access point on an existing network. The
OpenWrt defaults (jack 1 = LAN at 192.168.1.1 with a DHCP server, jack 2 = WAN) have not been tried on a unit yet.

### Not supported

- The 5G/LTE modem. Cellular modem support is not included; the unit works as a router or access point with a
  wired internet connection only.
- `sysupgrade`. To update, go back to the stock firmware and install the new image again. **This erases your
  OpenWrt settings and any packages you added**, so note or back them up first.
- OpenWrt in both slots. Always keep the stock firmware in one slot: it is the only way back. The install command
  refuses to run unless the stock firmware is running, so it never writes the stock firmware's own slot.

### Not tested

- Running for days or longer.
- Installing on a unit that runs the stock firmware from its second slot (slot B).
- 2.4 GHz with a client, and 160 MHz channels.
- USB 2 devices, and starting up with a USB device plugged in. Over-current protection on the USB port is not
  ported.
- Recovery without the stock firmware: no working serial-console recovery procedure has been established.

### Good to know

- **A stock firmware update overwrites OpenWrt.** When the stock firmware updates itself, it writes the slot it is
  not running from, which is the OpenWrt slot. (Read from the stock update script; not observed.)
- OpenWrt keeps its settings in its own slot (about 120 MiB). It does not use the stock firmware's data partition
  (`user_data`, about 3 GiB). Do not format that partition: the stock firmware keeps its data there.
- Packages you add with `apk` must come from the same build (`out/$STAMP/packages/`): every build has its own
  kernel and its own package signing key.

## Customizing the image

Files under `local/files/` are copied into the image (OpenWrt's `files/` mechanism). `local/` is not tracked by git.
Create them before `./build.sh start`. The build reads them as another user, so they must be readable by others on
your computer (for example `chmod 644`, and `chmod 755` for directories); the build sets the stricter permissions
that SSH needs inside the image.

- `local/files/etc/dropbear/authorized_keys`: your SSH **public** key, for example a copy of
  `~/.ssh/id_ed25519.pub`.
- `local/files/etc/uci-defaults/99-local`: a shell script run once on the first boot to change the defaults with
  `uci`, for example:

      uci set system.@system[0].hostname='air6'
      uci commit system
      exit 0

## Files from outside this repository

- **Wi-Fi firmware:** `./build.sh pull-fw` copies four files over SSH from the stock firmware of your unit into
  `local/firmware/` (not tracked by git). `stock-firmware.lock` lists their hashes as seen on stock firmware 1.01.36,
  1.01.46 and 1.01.52. A file with another hash (another stock version) is accepted with a warning, but has not been
  tested; `out/$STAMP/PROVENANCE` marks it.
- **Boot image tools:** downloaded from the LG6851F repository at the commit pinned in `externals.lock`. If any hash
  differs, the build stops.

## How the pieces fit together

| Part | In this repository | In the fork | How to check it |
| --- | --- | --- | --- |
| OpenWrt source | `fork.lock`, `./build.sh fetch` | branch `air6` | `fork.lock` commit = `openwrt fork:` in `PROVENANCE` |
| Boot image tools | `externals.lock`, `build/fetch-externals.sh` | - | `externals:` in `PROVENANCE` |
| Wi-Fi firmware | `stock-firmware.lock`, `./build.sh pull-fw`, `scripts/device/stock_wifi_fw.sh` | `package/kernel/mt76/patches/999-*` | `wifi firmware:` in `PROVENANCE`; on the unit, `dmesg \| grep mt7996e` shows the firmware build times |
| Build and signing | `build.sh`, `build/`, `docker/`, `config/` | - | `out/$STAMP/SHA256SUMS`, `PROVENANCE` |
| Image check | `scripts/check_image.sh`, `scripts/resign_boot.py` | - | `out/$STAMP/CHECK.txt` (one line per check) |
| Install and slot switch | `device.sh`, `scripts/device/` | - | `./device.sh status root@DEVICE` |
| Automatic return | - | `target/linux/mediatek/mt6990/base-files/usr/sbin/air6-abguard` | `air6-abguard status`, `logread -e air6-abguard` on the unit |

Every build writes `out/$STAMP/PROVENANCE`: the commits of the fork and of this kit, the downloaded files, and the
hashes of the Wi-Fi firmware. On the unit, `/etc/openwrt_release` shows the OpenWrt revision it was built from.
