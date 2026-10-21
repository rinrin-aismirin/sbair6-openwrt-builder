# The 5G modem (optional, experimental)

This page explains how to build an image that can use the Air 6's built-in modem. Without these steps the image has
no modem support, and the modem is switched off.

> [!CAUTION]
> The modem stores its data (calibration, the IMEI area, network settings) in NV partitions that the stock firmware
> uses too; they are not part of the A/B slots. Running the modem under OpenWrt writes to them. Back them up first
> (step 4) and keep the copy private: it contains data specific to your unit.

## How it works

The modem needs programs that only exist in the stock firmware. They have no licence that allows passing them on,
so this repository does not contain them: `./build.sh pull-modem` copies them from your own unit, and only your own
image gets them. **Do not pass on an image built with them** (or its packages directory). The `air6-modem` service
runs them in a chroot made from the copied files, with the stock libraries; it shares `/dev` and `/sys` with
OpenWrt and is not a security boundary.

The programs must come from the same stock firmware version as the modem firmware in the slot OpenWrt runs from.
The modem firmware of a slot is the one the stock firmware in that slot brought; installing OpenWrt does not change
it. So the programs have to be copied from the stock firmware in that slot **before OpenWrt is installed into it**.
`./device.sh install` refuses to put a build into a slot whose modem firmware has another version, and the service
refuses to start on such a slot. Both compare version names (from the stock root filesystem and from the slot's
`md1img`); this does not check the modem firmware's other parts or its integrity.

## What you need

- Everything from the [README](../README.md)'s "What you need".
- A SIM card that the unit accepts. The unit tested here was SIM-locked to SoftBank's networks; the lock is stored
  in the modem and is changed from the stock firmware (not described here). Its built-in eSIM held a SoftBank
  profile and did not accept other profiles (no profile manager on the chip), so other SIM cards go into the slot.
- The APN settings of your SIM card.

## 1. Copy the modem programs

With the unit on the stock firmware, before installing OpenWrt for the first time:

    ./build.sh pull-modem root@DEVICE

This reads the slot that does not run (the one OpenWrt will be installed into), and stores the programs under
`local/modem/<version>/`, for example `local/modem/V26_4_P48/`. The command checks the files against
`modem-files.lock` and warns about files it has not seen before.

If OpenWrt is already installed in that slot, its stock firmware is gone. Use a saved copy of that slot's stock
root filesystem instead (a squashfs image, for example from a backup of the `rootfs_a` or `rootfs_b` partition):

    ./build.sh pull-modem path/to/rootfs.img

## 2. Build with the modem

As in the README's [build step](../README.md), with `AIR6_MODEM=1` in front of `./build.sh start`:

    STAMP=$(AIR6_MODEM=1 ./build.sh start)
    echo $STAMP
    ./build.sh status $STAMP           # repeat until the last line says "result: done"
    ./build.sh collect $STAMP          # must print "RESULT: PASS"

`AIR6_MODEM=1` needs exactly one version under `local/modem/`; with several, name it, for example
`AIR6_MODEM=V26_4_P48`. The build adds the modem drivers, the `air6-modem` service and its LuCI pages, checks the
copied programs against the checksums `pull-modem` recorded, and lists them with the version in
`out/$STAMP/PROVENANCE` and `out/$STAMP/MODEM_FILES`.

## 3. Install

As in [install.md](install.md), with the `$STAMP` from step 2. `./device.sh install` first compares the version of
the copied programs with the modem firmware of the target slot (see above).

## 4. Back up the NV partitions

In LuCI: **Network → Air 6 modem**, **Back up NV partitions**. After about a minute the browser downloads
`air6-nv-<time>.tar.gz` (about 8 MB). Check that the file is in your downloads, then click **The file is saved**;
only then does the page count the backup as done. Until then the router keeps its copy, unless a later backup
succeeds: that one replaces it, and confirming the older one then fails. Keep this file somewhere safe.

To back up again later, disable the modem on the same page and save first: the backup refuses to read the
partitions while the modem uses them.

Or from the computer, with the modem service stopped (it is off after installing):

    ./device.sh nv-backup root@192.168.1.1

which saves the same archive to `out/air6-nv-<time>.tar.gz`. The archive holds the NV partitions, their
checksums and your unit's identity (the file system IDs of the NV partitions).

## 5. Turn the modem on

After the backup, the page shows **Enabled**. Tick it and save. The status table shows the modem as Ready after
about 10 seconds.

Or over SSH (after a backup with `device.sh`):

    uci set air6-modem.main.nv_backup_done=1
    uci set air6-modem.main.enabled=1
    uci commit air6-modem
    /etc/init.d/air6-modem start

## 6. Add the mobile data interface

In LuCI: **Network → Interfaces → Add new interface**, protocol **SoftBank Air 6 modem**, then enter the APN,
the authentication type and the user name and password of your SIM card. Put the interface in the `wan` firewall
zone if it should be the internet connection.

Or in `/etc/config/network`, for example:

    config interface 'wwan'
        option proto 'air6mipc'
        option apn 'example.apn'
        option auth 'chap'
        option username 'user'
        option password 'pass'

The modem uses the SIM slot if a card is in it, otherwise the built-in eSIM, like the stock firmware; the
**SIM** setting on the Air 6 modem page can fix either one. The choice is applied when the interface starts.

## What you see

- LuCI's Air 6 modem page: service, modem, SIM, network, signal and data interface, every 15 seconds. The same
  data comes from `ubus call air6-modem status`.
- Front LEDs while the service runs: SIM green (ready) or red (missing or locked); mobile blue (5G), green (LTE)
  or red (not registered); one to three signal LEDs. All off when the service is off.

## Known limitations

- After stopping the service the modem is switched off, but its drivers stay loaded until the next reboot.
- The modem keeps the APN it attaches with, and the stock firmware sets its own whenever it runs. The first data
  connection after that (for example the first one after going back from the stock firmware) can make the modem
  attach again, and this can drop the first call. While it sets up, the interface checks the call twice (a few
  seconds after making it and once more after coming up) and makes it again if it was dropped, so that connection
  takes about ten seconds longer. These checks are not an ongoing watch: a call lost later is not noticed by them.
- Starting the modem can fail: in one test (about 110 modem starts in total) the modem did not answer its start
  handshake (`MD_BOOT_HS1_FAIL` in `dmesg`) and stayed in its booting state. The cause is unknown. The service
  restarts the modem when it is not ready 90 seconds after a start (`ready_timeout` in `/etc/config/air6-modem`),
  at most twice per service start; after that the Air 6 modem page shows the error and the service has to be
  restarted by hand (see below). Stopping the service also ends these restarts. The automatic restart was tested
  by shortening the timeout, not with a real failed start.
- If the modem's helper processor does not confirm a stop within 40 seconds (counted after it was asked; the whole
  stop can take longer), the final reset of the data path is skipped and the modem cannot be used again until the
  next reboot: the service does not start, and the Air 6 modem page shows the error. This did not happen in the
  tests below, and it was not provoked on purpose. The vendor driver's reset of the helper processor does not check
  that the reset completed, so a confirmed stop relies on that driver.
- SMS, calls, eSIM profiles and the SIM lock are not handled.
- IPv6 is untested. The interface asks for IPv4 and IPv6 by default (**PDP Type**) and sets up an IPv6 address
  and route when the network gives one, but the SIM card tested here got IPv4 only: the network refused IPv6-only
  connections and answered IPv4/IPv6 requests with IPv4. The IPv6 address is the router's own; no prefix is passed
  on to the LAN.
- Tested so far on one unit (V26_4_P48 programs with V26_4_P48 firmware): the service, status and LEDs; starting,
  using (IPv4 data and ping) and stopping the modem repeatedly, up to five times in one boot and with about four
  seconds between a stop and the next start; an IPv4 data connection with a SoftBank-network MVNO SIM in the slot;
  "auto" with a card in the slot; switching between the slot and the built-in eSIM (expired profile: "not
  registered"); the backup over the router's web API (not yet clicked through in a browser). Not tested: "auto"
  with an empty slot, IPv6, roaming, and a restore of the NV partitions.
- Programs from another version (V26_4_P54 with V26_4_P48 firmware) started the modem in one test, but are refused
  unless `allow_version_mismatch` is set; data with such a pair is untested.

## When something goes wrong

The interface shows an error code:

| Code | Meaning |
|---|---|
| `MODEM_NOT_READY` | The service is not running or the modem did not start: check the Air 6 modem page. If it shows that the modem did not start, restart the service: `/etc/init.d/air6-modem restart`. |
| `SIM_NOT_INSERTED` | No SIM card. |
| `SIM_SLOT_FAILED` | The modem did not switch to the chosen SIM slot. |
| `SIM_LOCKED` | The SIM card asks for a PIN or PUK. |
| `SIM_NOT_READY` | The SIM card was not read in time. |
| `NOT_REGISTERED` | No network accepted the SIM card in time. |
| `CALL_FAILED` | The network refused the data connection (check the APN and the login), or the modem dropped the call while it was set up (the interface tries again; see the system log: `logread \| grep air6mipc`). |

The service writes why it did not start to the system log (`logread | grep air6-modem`): a missing NV backup
confirmation, missing programs, or a version mismatch.

To put the NV partitions back from a backup: disable the modem and save, then **Restore...** on the Air 6 modem
page and choose the archive. The router checks the archive (only the files a backup contains, their checksums and
sizes) and that it comes from the same unit, asks again, keeps a copy of the current partitions on the router (until
the next reboot), writes the backup and reads it back, then offers a reboot. If writing fails after the copy was
made, the page offers the copy for download. The button works only while the modem is disabled, and the last step
asks you to type `restore`. Restore exists for emergencies and has not been tried on a unit yet.

"The same unit" means that the file system IDs of the NV partitions match those in the archive. This is not a
proof of identity: a unit whose NV file systems were reformatted or damaged no longer matches its own backups.

## Technical notes

- Kernel: the vendor CCCI/CCMNI/DPMAIF/MEDMCU drivers as the `kmod-mt6990-modem` package (in the fork), loaded by
  the service only; the modem power domain is off whenever no driver uses it.
- Packages: the `air6-modem` service and its two LuCI packages are in this repository's `feed/`, which the build
  adds as the feed `air6` only with `AIR6_MODEM`. They do nothing without the stock files, so they are kept with
  the code that copies and checks those files, not in the fork.
- Runtime: the stock programs run in a chroot (overlay of `/usr/lib/air6-modem/stock` with a tmpfs) under
  `/tmp/air6-modem/`, with the NV partitions mounted where the stock firmware mounts them. Stopping the service
  ends the processes and unmounts everything.
- `modem-files.lock` lists the copied files (the eight modem programs, the libraries they load and a few data
  files, about 7 MB) and the hashes seen so far.
