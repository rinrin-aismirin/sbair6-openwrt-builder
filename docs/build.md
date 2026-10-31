# Building: customizing, options and records

The first build and install are in [docs/install.md](install.md). This page is the reference for what goes into a
build, how to change it, and what a build leaves behind.

## Build steps and failures

    ./build.sh start [OPTIONS]         # prints the build ID ($STAMP)
    ./build.sh status $STAMP           # the last line says result: running, done or failed
    ./build.sh collect $STAMP          # copies a finished build to out/$STAMP/ and prints the image check result
    ./build.sh logs $STAMP             # copies the logs of a build to out/logs-$STAMP/

- Only one build runs at a time: a second `start` is refused while one is running.
- A build reads this directory (including `local/`) and the fork checkout while it runs. Do not change them until
  `status` says done or failed; `PROVENANCE` records a kit input that changed during the build.
- If `status` says `result: failed`, run `./build.sh logs $STAMP` and look at the log files in `out/logs-$STAMP/`.
  `logs` does not replace an existing `out/logs-$STAMP/`: remove that directory to copy the logs again.
- `collect` never replaces an existing `out/$STAMP/` of another build.
- `./build.sh` without arguments prints all commands, including building another checkout of the fork and choosing
  the Docker context or volume.

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

`./build.sh start --no-local-files` builds without them (they stay where they are). When `local/files/` replaces
kernel modules, firmware, module settings, start-up scripts or package data, `start` lists those paths and
`PROVENANCE` records them. Scripts in `local/files/` can run while the image is made, not only on the unit.

## Build options

These change what is built, not only what is copied into the image. Each is used only when given, for example
`./build.sh start --local-config --kernel-patches`.

| Option | Uses | Effect |
| --- | --- | --- |
| `--trial` | - | A trial image; what that means: [docs/install.md](install.md#1-choose-what-to-build) |
| `--local-config` | `local/diffconfig` | OpenWrt configuration lines added after the kit's own |
| `--kernel-patches` | `local/kernel-patches/NNN-name.patch` | Patches added to the fork's kernel |
| `--all-kmods` | `config/all-kmods.exclude` | Every kernel module built as a package |

**`--trial`** adds `air6.trial=1` to the kernel command line of the image (the `/chosen/bootargs` of its device
tree); the image check reports it as `policy trial`. The policy belongs to the image: it is not carried over to a
later install.

**`--local-config`** adds the lines of `local/diffconfig`, for example `CONFIG_PACKAGE_kmod-usb-net-rtl8152=y`. A
package asked for with `=y` must still be `=y` after OpenWrt resolves the configuration, or the build stops before
compiling. Without the option, a `local/diffconfig` is not used (earlier versions of this kit used it
automatically); `start` says so.

**`--kernel-patches`** copies the patches into the fork's pending kernel patches
(`target/linux/generic/pending-<kernel>/`). A name that the fork already uses is refused.

**`--all-kmods`** builds every kernel module as a package, except those in `config/all-kmods.exclude`. This also
changes the kernel itself, so it is a different build, not the same image plus packages. `CONFIG_ALL`,
`CONFIG_ALL_NONSHARED` and `CONFIG_BUILDBOT` (which also select userspace packages) are refused with or without this
option.

The modem build is selected with `AIR6_MODEM=1` in front of `./build.sh start` ([docs/modem.md](modem.md)).

## What a build leaves behind

`out/$STAMP/` holds:

| File | What it is |
| --- | --- |
| `boot.img`, `rootfs.img` | The images for the boot and root partitions of a slot |
| `sysupgrade.bin` | The same boot image and squashfs as one package for `./device.sh upgrade` (OpenWrt's sysupgrade), with a `CONTROL` file (sizes, hashes, trial setting, modem version, commits) and fwtool metadata |
| `CHECK.txt` | The image check: one line per check, ending in `RESULT: PASS` or `RESULT: FAIL`. It checks hashes, sizes, the boot image signature and device tree, the trial setting against the build options, the files the board and the slot control need, and that `sysupgrade.bin` carries exactly these images. It cannot prove that the image boots |
| `PROVENANCE` | A record of the inputs (below). It does not say that the image works or was tested |
| `SHA256SUMS`, `PACKAGES.sha256` | Hashes of the images (with `sysupgrade.bin`) and of the packages |
| `packages/` | The packages of this build |
| `private/` | Your inputs as the build used them and the resolved configurations; readable by you only |

`PROVENANCE` gives the build class and options, the commits of the fork and of this kit (and any uncommitted change
to the kit's build files), the downloaded files, the hashes of the Wi-Fi firmware and of the resolved
configurations, and the kernel package version its kernel module packages depend on. The class is `reference` (the
fork in `fork.lock`, this kit's commit unchanged, no options, no modem, nothing from `local/files`),
`reference + rootfs overlay` (the same with `local/files`), or `modified:` followed by what differs. It describes the
inputs, not the result of a test.

On the unit, `/etc/openwrt_release` shows the OpenWrt revision the image was built from. That is the fork commit
only; the other inputs are in `PROVENANCE`.

**Packages:** packages you add with `apk` must come from the build whose image the unit runs
(`out/$STAMP/packages/` of that build): install that build's image first, then its packages, and do not force `apk`
past dependency checks. Every build has its own package signing key. Kernel module packages depend on a kernel
package version; two builds with the same version are not necessarily built from the same sources, so the version
alone does not make another build's modules safe to use.

## What may be passed on

The images and packages of a build can contain your `local/files/` (keys, passwords) and files whose redistribution
has not been cleared (see [Files from outside this repository](#files-from-outside-this-repository) and
[docs/modem.md](modem.md)). Do not assume that any file of a build may be given to others. `PROVENANCE`
holds no file contents from `local/`, but its paths, options and hashes can still describe your setup.

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
| Build and signing | `build.sh`, `build/`, `docker/`, `config/` | - | `out/$STAMP/SHA256SUMS`, `PACKAGES.sha256`, `PROVENANCE` |
| Image check | `scripts/check_image.sh`, `scripts/check_sysupgrade.py`, `scripts/dtb_bootargs.py`, `scripts/resign_boot.py` | - | `out/$STAMP/CHECK.txt` |
| Updates from OpenWrt | `device.sh upgrade`, `upgrade-check`, `build/make_sysupgrade.py` | `lib/upgrade/platform.sh`, `lib/air6/upgrade.sh` | `out/$STAMP/CHECK.txt` (sysupgrade lines), `air6-slot status` (last sysupgrade record) |
| Install and slot switch from the stock firmware | `device.sh`, `scripts/device/` | - | `./device.sh status root@DEVICE` |
| Slot control on OpenWrt | - | `target/linux/mediatek/mt6990/base-files/`: `usr/sbin/air6-slot`, `lib/air6/bootctrl.sh`, `etc/init.d/air6-slot*`, `lib/preinit/25_air6_slot_switch` | `air6-slot status`, `logread -e air6-slot` on the unit |
| Failsafe on the Air 6 | - | same directory: `lib/preinit/06_air6_preinit_iface`, `29_air6_failsafe_keys`, `31_air6_failsafe_keys` | the serial console during start-up |
| Modem (optional, [docs/modem.md](modem.md)) | `./build.sh pull-modem`, `modem-files.lock`, `feed/` (service and LuCI packages) | `kmod-mt6990-modem`, device tree | `modem:` in `PROVENANCE`, `out/$STAMP/MODEM_FILES` |
