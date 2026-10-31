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

## What this is

The SoftBank Air 6 (model A775) is a 5G home router built on a MediaTek MT6990 module, with tri-band Wi-Fi 7 and two
Ethernet jacks. This kit builds an OpenWrt SNAPSHOT image for it (from OpenWrt's main branch, not a release) on your
Linux computer and installs it over SSH.

The unit has two system slots. The stock firmware runs from one of them; the install writes OpenWrt into the other
one and never writes the stock firmware's slot, so the stock firmware stays as the way back.

Read these before you decide to install:

- **Updates write the other slot, and the first one overwrites the stock firmware.** `./device.sh upgrade` (OpenWrt's
  sysupgrade) keeps your settings and writes the slot OpenWrt is not running from, so OpenWrt then alternates between
  the two slots. The first update therefore replaces the stock firmware; it refuses to do so without a confirmed
  backup of the stock slot, and the way back to the stock firmware is then that backup
  ([updating](docs/install.md#updating-to-a-new-build)). sysupgrade is new: tried on one unit on one day.
- **A stock firmware update overwrites OpenWrt.** When the stock firmware updates itself, it writes the slot it is
  not running from, which is the OpenWrt slot. (Read from the stock update script; not observed.)
- **The 5G/LTE modem is off** in the default build (without modem support): the unit works as a router or access point with a wired internet
  connection only. An optional, experimental build includes modem support; it writes to partitions the stock
  firmware shares ([docs/modem.md](docs/modem.md)).
- **A normal image, once it has finished starting, is kept**, even if you cannot reach it over the network. The
  bootloader returns to the stock firmware by itself only when OpenWrt crashes and the unit resets before start-up
  finishes. A trial image (recommended for a first install) can also return by itself, if its return timer is armed
(check its status after the boot). For the other
  cases there are manual ways out (failsafe mode, a key held at power-on); see
  [How it works](docs/install.md#how-it-works).
- **OpenWrt's network defaults** (jack 1 = LAN at 192.168.1.1 with a DHCP server, jack 2 = WAN) have not been tried
  on a unit yet: the tests used an image set up as an access point on an existing network.

## Status

Tested on one unit, in short tests (hours, not days). The tested images used a local overlay that set the unit up as
an access point.

| Area | Tested | Not tested |
| --- | --- | --- |
| Install and boot | Install from the stock firmware on slot A; boot; return to the stock firmware by the bootloader after failed boots | Installing from a unit whose stock firmware runs from slot B |
| Updates (sysupgrade) | `./device.sh upgrade` both ways (B to A over the stock firmware, A to B); OpenWrt booting from slot A; settings carried over; an uncommitted trial image returning by its timer and by the bootloader after failed starts (recorded under "failed updates"); stopping without a reboot when the boot control bytes are uncertain (on a dry run) | Running many updates in a row; a power cut during an update |
| Going back to the stock firmware | A backup of the stock slot, and restoring it after OpenWrt had overwritten that slot: the stock firmware started and its modem found the SIM (it did not register with the SIM used, as before the overwrite: its APNs are SoftBank's) | Mobile data on the restored stock firmware |
| Keeping and leaving OpenWrt | Slot marked good at the end of start-up, staying across reboots; switching slots by holding the LEVEL key at power-on; failsafe mode with the WPS key. On an earlier build, before later fixes to the timer and the key handling: a trial image returning after 10 minutes, failsafe with the RESET key (the current timer code is tested on the host only) | Reaching failsafe mode (192.168.1.1) from a computer; the LEVEL key's error cases |
| Ethernet | Both jacks on the internal switch at 1 Gbit/s, traffic in both directions, a cable replug | |
| Wi-Fi (stock firmware files) | 2.4, 5 and 6 GHz bands present; one access point on 5 + 6 GHz (MLO, WPA3) with a Wi-Fi 7 phone at 80 MHz: about 925 Mbit/s from the phone, 760-790 Mbit/s to it (iperf3) | 2.4 GHz with a client; 160 MHz channels |
| USB | A USB 3 memory stick (FAT) at 5 Gbit/s on the Type-A port | USB 2 devices; starting up with a device plugged in |
| LEDs | Front panel and jack LEDs | |
| Long-term | | Running for days or longer |

Not supported:

- Recovery without the stock firmware: no working serial-console recovery procedure.
- Over-current protection on the USB port (not ported).
- The modem in the default build (optional build: [docs/modem.md](docs/modem.md)).

## What you need

- A Linux computer with Docker and git, and about 20 GB of free disk space (measured: build cache 13 GB, Docker
  image 1.2 GB, OpenWrt source 0.4 GB). Tested on x86_64 Debian 13 with rootless Docker; other setups have not been
  tried.
- The Air 6, running the stock firmware, and root SSH access to it. This kit does not set up that access.
- A computer you can plug into jack 1 of the Air 6, to reach OpenWrt after the install. It can be the same Linux
  computer.

## Where to go next

| You want to | Read |
| --- | --- |
| Build, install, check, go back to the stock firmware, or recover | [docs/install.md](docs/install.md) (one walk-through, from the build to the first login) |
| Put your SSH key or settings into the image, add packages, use the build options, read the build records | [docs/build.md](docs/build.md) |
| Use the 5G/LTE modem (experimental) | [docs/modem.md](docs/modem.md) |
| Use a USB 2.5G network adapter (RTL8156B) | [docs/usb-nic.md](docs/usb-nic.md) |

## What it is based on

- **OpenWrt:** a fork of OpenWrt main with the MT6990 platform and the Air 6 added,
  https://github.com/rinrin-aismirin/openwrt (branch `air6`). The kernel support comes from an OpenWrt tree for
  another MT6990 board, the FiberHome LG6851F: https://github.com/13179415360/openwrt-mt6990-lg6851f.
- **Wi-Fi firmware:** copied over SSH from the stock firmware of your own unit.
- **Boot image tools:** the boot image packer and the signing tool with the MT6990 SDK test keys, which the stock
  bootloader accepts, are downloaded from the LG6851F repository when you build.

The files from the stock firmware and from the LG6851F repository are not part of this repository: we have not found
a licence that allows redistributing them. The kit fetches them itself and checks them by hash
([docs/build.md](docs/build.md#files-from-outside-this-repository)).
