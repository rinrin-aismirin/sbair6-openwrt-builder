# Partitions

This page lists the Air 6's eMMC partitions, which of them belong to a slot, and which tool writes which. The slots
and the boot control record are explained in [boot-control.md](boot-control.md).

## The partition table

The eMMC has a GPT with 43 partitions. The table below is from unit 1 (read 2026-10-17); unit 2 has the same table
except for the size of `user_data`. Sizes are rounded.

| # | Name | Size | Belongs to | Notes |
| --- | --- | --- | --- | --- |
| 1 | `misc` | 512 KiB | shared | Boot control record ([boot-control.md](boot-control.md)) |
| 2 | `expdb` | 20 MiB | shared | |
| 3 | `nvcfg` | 1 MiB | shared | NV (modem and unit data); ext4 |
| 4 | `nvdata` | 64 MiB | shared | NV; ext4 |
| 5, 6 | `protect1`, `protect2` | 8 MiB each | shared | NV; ext4 |
| 7, 8 | `mcf1_a`, `mcf2_a` | 8 MiB each | slot A | Modem data of the slot; ext4 |
| 9, 10 | `mcf1_b`, `mcf2_b` | 8 MiB each | slot B | Modem data of the slot; ext4 |
| 11 | `seccfg` | 512 KiB | shared | All zero on unit 1 |
| 12 | `boot_para` | 2 MiB | shared | |
| 13 | `nvram` | 40 MiB | shared | NV |
| 14-24 | `connsys_gnss_a`, `md1img_a`, `md1dsp_a`, `spmfw_a`, `pi_img_a`, `dpm_a`, `medmcu_a`, `sspm_a`, `mcupm_a`, `lk_a`, `tee_a` | 8, 80, 10, then 1 MiB each | slot A | Firmware of the bootloader, modem and helper processors |
| 25 | `boot_a` | 32 MiB | slot A | Boot image |
| 26 | `rootfs_a` | 128 MiB | slot A | Root file system and settings |
| 27-37 | `connsys_gnss_b` ... `tee_b` | as slot A | slot B | As 14-24 |
| 38 | `boot_b` | 32 MiB | slot B | Boot image |
| 39 | `rootfs_b` | 128 MiB | slot B | Root file system and settings |
| 40 | `raw1` | 2 MiB | shared | Factory data ([below](#raw1-factory-data)) |
| 41 | `raw2` | 2 MiB | shared | |
| 42 | `qraw` | 3 MiB | shared | |
| 43 | `user_data` | about 3 GiB | shared | The stock firmware's `/data`; ext4 |

Outside the GPT, the eMMC boot areas `boot0` and `boot1` hold the preloader (identical on unit 1).

A slot is 15 partitions: the 11 of rows 14-24 (or 27-37), `mcf1`, `mcf2`, `boot` and `rootfs`. In the dumps of
2026-10-17, the two slots of each tested unit held different stock firmware releases in these partitions.

The Air 6 tools find partitions by name (`PARTNAME` in `/sys/block/mmcblk0/mmcblk0p*/uevent`), not by number.

## Who writes what

| Who | Writes |
| --- | --- |
| `./device.sh install` (from the stock firmware) | `boot_X` and `rootfs_X` of the other slot (the whole 128 MiB `rootfs.img`), then the boot control record |
| `./device.sh switch` (from the stock firmware) | The boot control record only |
| `air6-slot`, the trial timer, the LEVEL key | The boot control record only |
| sysupgrade (`./device.sh upgrade`) | `boot_X`, the start of `rootfs_X` (squashfs and settings area), the boot control record ([sysupgrade.md](sysupgrade.md)) |
| `air6-stock restore` (`./device.sh restore-stock`) | `mcf1_X`, `mcf2_X`, `boot_X`, `rootfs_X`, the boot control record ([stock-backup.md](stock-backup.md)) |
| `air6-stock backup`, `verify` | Nothing (they read) |
| OpenWrt while it runs | The settings area in `rootfs_` of its own slot |
| The modem service (optional build) | Mounts `nvcfg`, `nvdata`, `protect1`, `protect2` and `mcf1`, `mcf2` of its slot, and the modem writes to them. The NV restore on its LuCI page writes `nvcfg`, `nvdata`, `protect1`, `protect2`, `mcf1` and `mcf2` of both slots, and `nvram` ([features/modem.md](../features/modem.md)) |
| The stock firmware | While it runs: its own slot's `rootfs`, `mcf1`, `mcf2`; the boot control record (it marks its slot good); the shared NV (its modem); `user_data`. Its updater writes the slot it does not run from, copies per-slot partitions from its own slot, sets the boot control record and zeroes `boot_para` (read from its update script; not observed) |

Nothing in this kit or the fork writes the preloader, `lk`, `tee` or any other of the 11 firmware partitions of a
slot, `user_data`, or the shared partitions other than `misc` (the modem build aside).

## The boot partition

`boot_a` and `boot_b` hold an Android boot image (version 2) with MediaTek's signature appended. The bootloader (LK)
checks that signature; the kit signs with the MediaTek SDK test keys, which it accepts. The root file system is not
signature-checked.

The kernel command line comes from the device tree in the boot image (`/chosen/bootargs`) plus what LK adds, such as
`bootslot=a` or `bootslot=b`. The command line in the boot image header does not reach the kernel.

## The rootfs partition

`rootfs_a` and `rootfs_b` hold the squashfs of the build from the start of the partition. OpenWrt keeps its settings
in an f2fs overlay behind it: from the end of the squashfs, rounded up to 64 KiB, to the end of the partition (about
120 MiB). Each slot therefore has its own settings.

- `./device.sh install` writes all 128 MiB (the squashfs and zeros), so the slot starts with an empty settings area.
- sysupgrade writes only the squashfs and the first bytes of the settings area
  ([sysupgrade.md](sysupgrade.md#settings)).

**How a slot finds its rootfs:** the bootloader replaces `root=/dev/mmcblk0p24` with partition 26 or 39
([boot-control.md](boot-control.md#how-the-bootloader-uses-them)). Partition 24 itself is `tee_a`: the value only
serves as the string the bootloader replaces.

## raw1: factory data

`raw1` holds the unit's factory data, each part twice:

- An ASCII `key=value` block. OpenWrt reads `mac0` for the `lan` interface and `mac1` for `wan`
  (`/etc/board.d/02_network`). The block also holds the serial number, the default passwords and SSIDs.
- The Wi-Fi calibration data (EEPROM, 7680 bytes at offset `0x100000`). The Wi-Fi driver reads it through the device
  tree and does not start the radio without it ([hardware.md](hardware.md#wi-fi)).

OpenWrt only reads `raw1`. Its content is specific to the unit.

## user_data

`user_data` is the stock firmware's `/data` (ext4). OpenWrt does not mount it, write it or format it. Leaving it
untouched is also what lets a restored stock firmware find its own data.
