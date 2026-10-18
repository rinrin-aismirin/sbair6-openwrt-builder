# Installing and removing OpenWrt

This page walks through installing a build, checking it, and going back to the stock firmware. Read the warning at
the top of the [README](../README.md) first.

## How it works

The Air 6 has two system slots, A and B. The stock firmware runs from one of them. The install writes OpenWrt into
the other one and tells the bootloader to try it next. The slot with the stock firmware is never written, so it
stays as the way back.

Two things bring the unit back to the stock firmware on their own:

- If OpenWrt crashes or hangs and the unit resets, the bootloader gives up on OpenWrt after two attempts (about
  2 minutes each).
- If OpenWrt starts but you do not confirm it, `air6-abguard` switches back and reboots. It starts its 10-minute
  timer early in OpenWrt's start-up. This covers the case where OpenWrt runs but you cannot reach it.

Not covered: an image that hangs before `air6-abguard` starts, without the unit resetting. Pulling the power does
not count as a failed attempt either, so power cycling does not bring the stock firmware back.

In the commands below, `root@DEVICE` is the unit while it runs the stock firmware, and `root@192.168.1.1` is the unit
while it runs OpenWrt (from a computer on jack 1). `$STAMP` is the build ID, the name of a directory under `out/`.

## Before you start

Check the build:

    tail -n 1 out/$STAMP/CHECK.txt

It must say `RESULT: PASS`. `./device.sh install` refuses builds that did not pass.

Check the unit:

    ./device.sh status root@DEVICE

On the stock firmware this prints the running slot and the boot control bytes, for example:

    00:03:51 bootslot=a uptime=959.17 bootctrl=0f000101000e00010100

`bootslot=a` means the stock firmware runs from slot A, so OpenWrt will go into slot B. (The bytes are explained in
[Technical notes](#technical-notes).)

Keep `out/$STAMP/` after installing: switching back to this build later needs it.

## 1. Install

    ./device.sh install root@DEVICE $STAMP

This uploads the two image files (160 MiB) and writes them into the other slot. It does not reboot. When it worked,
the output ends with:

    boot_b and rootfs_b written and verified
    ...
    slot b preferred, retry preset 02
    installed; next: ./device.sh reboot root@DEVICE

(`slot a` instead of `slot b` if the stock firmware runs from slot B.)

If it ends any other way, do not reboot yet; see [When something goes wrong](#when-something-goes-wrong).

## 2. Reboot and confirm

Before rebooting, plug a computer into jack 1. With OpenWrt's defaults it gets an address in 192.168.1.0/24 from
OpenWrt; if that computer is also connected to another network using 192.168.1.0/24, disconnect it. (These defaults
are what the image is built with, but they have not been tried on a unit yet: the tests used an image set up as an
access point.)

    ./device.sh reboot root@DEVICE

OpenWrt took about 70 seconds to answer in our tests. Within 10 minutes of the reboot:

    ./device.sh confirm root@192.168.1.1

or, from a computer without this kit:

    ssh root@192.168.1.1 air6-abguard confirm

The output ends with `revert cancelled for this boot`.

On the first login, root has no password (OpenWrt's default). Set one with `passwd`, or put your public key into
the image before building (see the README).

OpenWrt has new SSH host keys. If your computer connected to 192.168.1.1 before, ssh refuses and shows the old key.
Check that you are connected to the Air 6 on jack 1, then remove only that entry and connect again:

    ssh-keygen -R 192.168.1.1

If the unit comes back with the stock firmware instead, OpenWrt did not start or was not confirmed in time. The
stock firmware and its slot are unchanged; you can try again from step 1.

## 3. Check that it works

Do this before you rely on OpenWrt or commit to it (`ssh root@192.168.1.1`):

- From the computer on jack 1, open LuCI at http://192.168.1.1, or log in with SSH.
- Plug the internet connection into jack 2 (WAN). `ip -4 addr show wan` shows an address, and
  `ping -c 3 openwrt.org` answers.
- Optional: plug in a USB memory stick. `dmesg | tail` shows it, and `ls /dev/sd*` lists the disk and its
  partitions.
- `cat /tmp/sysinfo/board_name` says `softbank,air6`.

For a closer look:

- `dmesg | grep mt7996e` shows the Wi-Fi firmware build times. With the firmware listed in `stock-firmware.lock`
  they are: ROM patch `20230704161925a`, WM `20240315201529`, DSP `20231113135337`, WA `20240315201449`. If your
  firmware had another hash (`pull-fw` warned about it), other times are expected; check `out/$STAMP/PROVENANCE`.
  There must be no `eeprom load fail`, `no valid board EEPROM` or `timeout` lines.
- `dmesg | grep "PCS detected"` shows two lines: the Ethernet links to the switch were found.

Wi-Fi is off until you turn it on in LuCI or with `uci`. Read the warning in the README first.

## Keeping OpenWrt across reboots

`confirm` only covers the current boot. Until you commit, every OpenWrt boot needs its own `confirm` within
10 minutes, and the bootloader still counts boots: one more reboot starts OpenWrt again, the one after that starts
the stock firmware.

To keep OpenWrt, after checking it as in step 3:

    ssh root@192.168.1.1 air6-abguard commit

After this the bootloader treats OpenWrt as good, and the automatic return no longer happens. `to-stock` still
works.

## Going back to the stock firmware

    ./device.sh to-stock root@192.168.1.1

The unit reboots into the stock firmware. OpenWrt stays in its slot.

To boot that OpenWrt again later without installing it again (the unit runs the stock firmware):

    ./device.sh switch root@DEVICE $STAMP
    ./device.sh reboot root@DEVICE

`switch` checks that the boot partition of the OpenWrt slot matches `out/$STAMP/boot.img`; it does not check the
rest of the slot. Then confirm as in step 2.

## Updating to a new build

There is no in-place update. Go back to the stock firmware, then install the new build (steps 1 to 3). The install
replaces the whole OpenWrt slot, so your OpenWrt settings and added packages are lost.

## When something goes wrong

Common messages from `./device.sh install`:

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

If OpenWrt starts but you cannot reach it, wait: within 10 minutes `air6-abguard` returns to the stock firmware.

## Technical notes

- The boot control bytes (`bootctrl=`) are 10 bytes in the `misc` partition: slot A priority, retry count, success
  flag, update type, one unused byte, then the same for slot B. The slot with priority `0f` boots. Before an install
  from slot A they read for example `0f000101000e00010100` (A preferred and successful). After the install they read
  `0e000101000f02000100` (B preferred, retry 02, not yet successful); from slot B, `0f020001000e00010100`.
- The install uses the stock firmware's own script (`/lib/upgrade/bootctrl.sh`, `change_slot_info`) and sets the
  new slot's retry count to 02. The bootloader increments it at every boot of that slot and switches to the other
  slot when it reads 4: OpenWrt boots twice (retry 3 and 4), the third boot goes to the stock firmware.
- The same image works in either slot: the bootloader replaces `root=` on the kernel command line with the booted
  slot's root partition. Installing into slot A (from a unit whose stock firmware runs from slot B) has not been
  tested yet.
- `./device.sh status root@192.168.1.1` on OpenWrt runs `air6-abguard status`, which shows the same bytes per slot.
- The image check (`scripts/check_image.sh`, result in `out/$STAMP/CHECK.txt`) verifies the file hashes and sizes,
  the boot image signature and device tree, `air6-abguard` and its start-up link, the four Wi-Fi firmware files,
  that no default Wi-Fi calibration file is included, and the board's network setup. It cannot prove that an image
  boots.
