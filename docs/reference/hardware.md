# Hardware

This page lists the parts of the Air 6 that the OpenWrt port drives and how they are set up, as described by the
fork's device tree and board files. What has been tried on a unit is in [status.md](status.md).

## Board

| Item | Value |
| --- | --- |
| Model | SoftBank Air 6 (A775) |
| SoC | MediaTek MT6990 |
| Device tree | `target/linux/mediatek/dts/mt6990-softbank-air6.dts` on `mt6990.dtsi` (fork) |
| OpenWrt board name | `softbank,air6` (image profile `softbank_air6`, target `mediatek/mt6990`) |
| Storage | eMMC, 8-bit bus ([partitions.md](partitions.md)) |
| Serial console | `ttyS0`, 115200 baud (kernel command line); this kit has no procedure for attaching to it |

The device tree, the board files (`/etc/board.d/`, `/lib/preinit/06_air6_preinit_iface`, `/lib/upgrade/platform.sh`)
and the `air6-tools` package are in the fork; see [build.md](../build.md#how-the-pieces-fit-together).

## Ethernet

The two jacks are ports of a MediaTek MT7531 switch:

| Jack | Switch port | OpenWrt interface | MAC address |
| --- | --- | --- | --- |
| 1 | 1 | `lan` | `mac0` from `raw1` |
| 2 | 2 | `wan` | `mac1` from `raw1` |

- The switch is on MDIO address `0x1f` and connects to the SoC's second Ethernet MAC (`gmac1`) over a 2500base-x
  fixed link. The jacks run at up to 1 Gbit/s.
- This follows the stock firmware's switch setup (port 1 in VLAN 1, port 2 in VLAN 2). The MAC addresses are the
  ones the stock firmware uses on `br-lan` (`mac0`) and gives to `wan` (`mac1`) (`/etc/board.d/02_network`).
- The SoC's first MAC (`gmac0`) is disabled. On the stock firmware it reports a Realtek RTL8221B 2.5G PHY, which is
  not wired to either jack as far as a plug test on unit 1 showed (2026-10-17).
- Failsafe mode uses `lan` (jack 1) (`06_air6_preinit_iface`; [keys-and-failsafe.md](keys-and-failsafe.md)).
- A USB 2.5G network adapter is an optional feature: [features/usb-nic.md](../features/usb-nic.md).

## Wi-Fi

- One MediaTek Wi-Fi chip on PCIe, driven by OpenWrt's mt76 driver (`kmod-mt7996e`): PCI IDs `14c3:7990` on the
  first PCIe controller and `14c3:7991` (its second interface) on the second. mt76 handles it as an MT7996; the stock
  firmware calls it MT7990. The third PCIe controller is enabled, but nothing is detected on it.
- One wireless device (`phy0`) with three bands, 2.4, 5 and 6 GHz. OpenWrt's configuration shows them as three
  radios: `radio0` (2.4 GHz), `radio1` (5 GHz) and `radio2` (6 GHz).
- Firmware: four files (`mt7996_wm_mt6990.bin`, `mt7996_wa_mt6990.bin`, `mt7996_dsp_mt6990.bin`,
  `mt7996_rom_patch_mt6990.bin`) copied from the stock firmware of your own unit by `./build.sh pull-fw`
  ([build.md](../build.md#files-from-outside-this-repository)).
- Calibration: only the unit's own EEPROM in `raw1` ([partitions.md](partitions.md#raw1-factory-data)). The fork's mt76
  patch `999-mt7996-mt6990-firmware-and-board-eeprom.patch` refuses to start the radio without it instead of using
  default calibration data, and the image check (`CHECK.txt`) requires that no default EEPROM file is in the image.
- Wi-Fi is off after installation, as in OpenWrt by default; see the caution in the [README](../../README.md).

## USB

- One Type-A port on the SoC's USB controller (`kmod-usb-mtu3`), run as host only (`dr_mode = "host"`), with a USB 2.0
  and a USB 3 bus.
- VBUS is switched by GPIO 46 (regulator `usb_vbus`).
- Not ported: USB dual-role (OTG) switching, which the stock firmware runs, and the over-current input.
- Packages in the image: `kmod-usb-storage`, `kmod-fs-vfat` and the code pages `cp437`, `iso8859-1` and `utf8`.

## Keys

Three keys: RESET, WPS and LEVEL. Their GPIOs and what they do: [keys-and-failsafe.md](keys-and-failsafe.md#the-keys).

## LEDs

**Front panel:** 15 LEDs on an Awinic AW9523B LED controller (device tree node `i2c2`, address `0x5b`, reset on
GPIO 11). The fork adds its driver. Names in `/sys/class/leds/`:

| LED | Colours | Set up by OpenWrt |
| --- | --- | --- |
| Power | `red:power`, `green:power` | Green while starting, running and updating, red in failsafe mode (OpenWrt's `diag.sh` through the device tree `led-*` aliases); red blinking when sysupgrade stops ([sysupgrade.md](sysupgrade.md#how-a-run-ends)) |
| Status | `green:status` | On while `br-lan` has a link |
| Wi-Fi | `blue:wlan`, `red:wlan`, `green:wlan` | Blue: on while the radio `phy0` is on (`phy0radio`) |
| Mobile | `red:mobile`, `green:mobile`, `blue:mobile` | Not set |
| SIM | `red:sim`, `green:sim` | Not set |
| Signal bars | `red:signal-1`, `blue:signal-1`, `blue:signal-2`, `blue:signal-3` | Not set; the LEVEL key's slot switch uses them ([keys-and-failsafe.md](keys-and-failsafe.md)) |

**Jack LEDs:** each jack has two LEDs on SoC GPIOs. The MT7531's own LED outputs are not used.

| LED | GPIO | Lights for |
| --- | --- | --- |
| `led1_ethlan1` | 196 | Jack 1 (`lan`) linked at 1000 Mbit/s |
| `led0_ethlan1` | 198 | Jack 1 linked at 100 Mbit/s |
| `led1_ethlan2` | 199 | Jack 2 (`wan`) linked at 1000 Mbit/s |
| `led0_ethlan2` | 197 | Jack 2 linked at 100 Mbit/s |

As on the stock firmware, they show the link only and do not blink for traffic (`/etc/board.d/01_leds`). The 100
Mbit/s mapping follows the stock firmware's LED names; it was not observed with a 100 Mbit/s link.

The device tree also has two GPIO LEDs taken from the stock device tree, `5g_evb_sim` (GPIO 18) and `5g_evb_system`
(GPIO 16); OpenWrt does not set them.

## Modem

The unit has a built-in 5G/LTE modem. The default build has no modem support; an optional, experimental build adds
it: [features/modem.md](../features/modem.md).
