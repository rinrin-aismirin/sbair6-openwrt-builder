# Status

This page lists what has been tried on a unit, what has not, and what is not supported. Read the
[overview](README.md#overview) first for the terms; the mechanisms are on the other reference pages.

Everything under Tested was tried on one unit, in short tests (hours, not days), in 2026. The tested images used a local
overlay that set the unit up as an access point on an existing network. "The current code" means the Air 6 tools as
in the fork commit that `fork.lock` pins; the builds named below as current have the same tools.

## Tested

### Install and boot

- Install from the stock firmware on slot A into slot B, and the first boot (repeatedly, 2026-10-26 to 2026-10-31
  11:50, with earlier builds; on 2026-11-01 with the current build 20261101-002232-67934be6, a trial image: about
  75 s after the reboot the status showed `policy=trial`, `timer=armed` and `root=rootfs_b`).
- The slot marked good by itself at the end of start-up (normal images, repeatedly).
- Return to the stock firmware by the bootloader after failed boots (2026-10-17, a root file system erased by a test
  script, the retry count starting at 00).
- Booting the same OpenWrt again from the stock firmware (`./device.sh switch`, repeatedly).

### Updates (sysupgrade)

With the current build 20261101-002232-67934be6 (a trial image, fork 67934be6ac), on 2026-11-01 (00:23-00:48):

- `./device.sh stock-backup` of slot A (confirmed), then `./device.sh upgrade` with the same build from slot B to
  slot A over the stock firmware: `upgrade-check` said "written, and the unit runs the new slot a on rootfs_a"; the
  new slot was a trial with `timer=armed`, and `trial-commit` after the update kept it ("slot a committed").
- An update from LuCI's "Flash new firmware image" with `out/$STAMP/sysupgrade.bin` of the same build ("Keep
  settings" checked), from slot A to slot B, once: the unit came back on slot B with `policy=trial` and
  `timer=armed`; the "last sysupgrade record" in `air6-slot status` showed `state=written`, `from=a`, `to=b` and
  the sha256 of `sysupgrade.bin`; the SSH host key was unchanged; `trial-commit` kept it. `upgrade-check` was not
  used (there is no request record for a LuCI update).

On 2026-10-31 (20:21-20:27), from OpenWrt build 20261031-124627-eb3b028e in slot B (its Air 6 tools are the same
as the current ones) with the stock firmware in slot A:

- `./device.sh upgrade` without a confirmed backup of the stock slot: refused, nothing written. The slot had been
  backed up and confirmed earlier, but that confirmation was lost with an update in between (the confirmation is not
  carried over by sysupgrade; [sysupgrade](sysupgrade.md#settings)).
- `./device.sh stock-backup`, then `./device.sh upgrade` with build 20261031-192819-083d5306 (another build than the
  one in slot B) from slot B to slot A over the stock firmware: `upgrade-check` said "written, and the unit runs the
  new slot a" (on `rootfs_a`); slot A then started and was marked good.

Earlier on 2026-10-31:

- `./device.sh upgrade` from slot B to slot A over the stock firmware, writing the same build the unit ran, with a
  build from before a later fix to `root=` (the write and the backup check; 11:50-12:01).
- Updates both ways between OpenWrt slots with the current code; OpenWrt running from slot A on its own root file
  system.
- Settings carried over (a uci setting and the SSH host key), with a build from before the current root checks.
- An uncommitted trial image after an update returning by its timer (current code).
- An uncommitted trial image after an update returning by the bootloader after two warm reboots, recorded under
  "failed updates".
- The stop with the red LED, imitated by a test script, left with `reboot -f` over the serial console.

### Going back to the stock firmware

- A backup of the stock slot, and a restore of the same bytes into a slot that still held the stock firmware
  (2026-10-30, an earlier version of the restore tool).
- The backup check (`air6-stock verify`) refusing a backup after the stock firmware had run again (2026-10-30, an
  earlier version of the tool).
- A restore after OpenWrt had overwritten the slot by sysupgrade (2026-10-31, current code): the stock firmware
  started on the first try, and its modem found the SIM. It did not register with the SIM used, as before the
  overwrite, because the stock firmware's APNs are SoftBank's.
- A backup of the stock slot with the current code (2026-10-31, 20:2x; again on 2026-11-01).
- A restore of slot A from a backup while OpenWrt ran from slot B, with the current build (2026-11-01): after the
  reboot the stock firmware 1.01.52 started on slot A and marked it good.

### Keeping and leaving OpenWrt

- A marked-good slot staying across warm reboots (five warm reboots, 2026-10-26, on an earlier build).
- A trial image returning after 10 minutes after an install from the stock firmware (2026-10-26, on an earlier
  build). After an update: see [Updates](#updates-sysupgrade).
- A trial image kept with `trial commit` (2026-10-26, on an earlier build; after an install and after an update on
  2026-11-01 with the current build).
- `set-active` to the other slot and a reboot (repeatedly; with the current build on 2026-11-01).
- Switching slots by holding the LEVEL key at power-on (2026-10-26; again on 2026-10-28 with the current hook file),
  and cancelling by releasing it during the countdown (2026-10-26).
- Failsafe mode with the WPS key (2026-10-28, with key hooks that differ from the current ones in comments only):
  192.168.1.1 set on jack 1, left with `reboot -f` over the serial console.
- Failsafe mode from the serial console (`f`, 2026-10-26).
- On an earlier build, before later fixes to the key handling: failsafe mode with the RESET key (2026-10-28).
- A short RESET press on running OpenWrt rebooting the unit (2026-10-28).

### Hardware

On earlier builds, from 2026-10-18:

- Ethernet: both jacks on the internal switch at 1 Gbit/s, traffic in both directions, a cable replug.
- Wi-Fi (stock firmware files): 2.4, 5 and 6 GHz bands present; one access point on 5 + 6 GHz (MLO, WPA3) with a
  Wi-Fi 7 phone at 80 MHz: about 925 Mbit/s from the phone, 760-790 Mbit/s to it (iperf3).
- USB: a USB 3 memory stick (FAT) at 5 Gbit/s on the Type-A port.
- LEDs: front panel and jack LEDs.

## Not tested

### Install and boot

- Installing from a unit whose stock firmware runs from slot B (OpenWrt into slot A from the stock firmware).
- Another stock firmware version (`pull-fw` warns about the hash and goes on).
- OpenWrt's network defaults (jack 1 = LAN at 192.168.1.1 with a DHCP server, jack 2 = WAN).
- An image that hangs during start-up: whether the unit resets by itself, so that the bootloader counts the attempt.

### Updates (sysupgrade)

- A crash of a new slot after an install or update (retry count preset to 02): how many attempts and how long until
  the bootloader returns ([boot control](boot-control.md#how-the-bootloader-uses-them)).
- Running many updates in a row.
- A power cut during an update.
- The shipped stop code (red LED) and a power cycle out of it.
- `upgrade-check` saying "written, but the unit runs the old slot again": the record has to survive the restarts.
- A build with the modem ([modem](../features/modem.md)).
- `--no-config`.
- LuCI's "Flash new firmware image" from slot B to slot A, more than once, or with "Keep settings" unchecked; a
  manual `sysupgrade` on the command line.

### Going back to the stock firmware

- Mobile data on the restored stock firmware.
- A stock firmware update overwriting the OpenWrt slot (read from the stock update script; not observed).

### Keeping and leaving OpenWrt

- Reaching failsafe mode (192.168.1.1) from a computer.
- The LEVEL key's error cases (red LED; held more than 60 seconds).
- The LEVEL and WPS keys with build 20261031-192819-083d5306 or 20261031-124627-eb3b028e: the key hook files are the
  same as on the build tried on 2026-10-28 apart from comments; `air6-slot`, which the LEVEL key runs, has changed
  since.
- Repeated failsafe sessions reaching the bootloader's limit and switching slots (expected from the code;
  [keys](keys-and-failsafe.md#failsafe-mode)).
- Factory reset (RESET held 5 seconds or more).

### Hardware

- Wi-Fi: 2.4 GHz with a client; 160 MHz channels.
- USB: USB 2 devices; starting up with a device plugged in.
- Running for days or longer.

## Not supported

- Recovery of a unit on which neither slot starts: there is no supported or tested serial-console recovery procedure.
- Updating OpenWrt in the slot it runs from (`sysupgrade -s` is refused), and so keeping the stock firmware in a slot
  while updating OpenWrt ([sysupgrade](sysupgrade.md)).
- Over-current protection on the USB port (not ported).
- The modem in the default build (optional build: [modem](../features/modem.md)).
