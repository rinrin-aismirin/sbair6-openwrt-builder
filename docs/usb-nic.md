# A USB 2.5G network adapter (optional, experimental)

The Air 6 has two 1G LAN ports. Its USB 3 Type-A port can take a USB network adapter. This page covers adapters
with a Realtek RTL8156B (2.5G), driven by `r8152`. Only one adapter has been tested (below); other chips and
adapters are not covered.

> [!NOTE]
> Over-current protection on the USB port is not ported (see the README's Status). The adapter draws its power from
> that port.

## What was tested

| Item | Value |
|---|---|
| Adapter | UGREEN USB-A 2.5GbE, USB ID `0bda:8156`, `bcdDevice` `31f4` |
| Driver and firmware | `r8152` v1.12.13, `rtl8156b-2 v3 10/20/23` (from `r8152-firmware`) |
| Link | SuperSpeed 5000 to the unit, 2500/full to a 10GBASE-T switch port |
| Test | `iperf3`, the unit as one end, one TCP stream for 15 s; four streams gave about the same totals |

Not tested: running for a long time, traffic bridged between Wi-Fi and the adapter, other adapters, and the build
options of this page on any image other than the author's (which also had access-point settings in `local/files`).

## 1. Include the driver

The image has no package repository, so the driver must be in the build. Put this line in `local/diffconfig` and
build with `--local-config` (see "Build options for developers" in the README):

    CONFIG_PACKAGE_kmod-usb-net-rtl8152=y

    STAMP=$(./build.sh start --local-config)

This also selects `r8152-firmware`. Then follow the README from `status` to `collect` and install the image.

With only this step, the author measured about 1.4 Gbit/s from the unit and 2.2 Gbit/s to it.

## 2. Optional: tuning observed to reach 2.5G line rate

What was observed in this setup (not a general rule for other hosts, adapters or traffic):

| Direction | Observation | What helped |
|---|---|---|
| From the unit (TX) | One CPU core was nearly busy (IRQ and softirq). A larger `r8152` TX buffer raised the speed; more TX buffers did not. Which effect of the larger buffer (fewer USB transfers, larger TSO, deeper queue) mattered was not isolated. | `agg_buf_sz=65536`, a module parameter added by the patch below |
| To the unit (RX) | The core that takes the USB interrupt was fully busy. | NAPI in a kernel thread for the adapter |

Measured on the tested adapter, RPS (packet steering) active (Mbit/s, sender side):

| Setting | From the unit | To the unit | Built as |
|---|---|---|---|
| Driver only (step 1) | 1408 | 2178 | stock `r8152` |
| buffer 32768 | 1894 | 2201 | a test module with a fixed buffer size |
| buffer 65536 | 2351 | 2211 | a test module with a fixed buffer size |
| buffer 65536 and threaded NAPI | 2347 | 2346 | a test module with a fixed buffer size |
| `agg_buf_sz=65536` and threaded NAPI | 2345 | 2342 | the patch below |
| the same, set up at boot from the image (2c) | 2329 | 2320 | the patch below, committed to a local fork branch (before `--kernel-patches` existed) |

When the adapter's RPS setting was lost (the module reloaded without packet steering applied again), the speed fell
to about 0.9 Gbit/s from the unit and 1.5 Gbit/s to it (reported in the author's notes; raw output not kept).

What these settings affect, beyond this adapter:
- `agg_buf_sz` applies to every device the `r8152` module drives. Each device gets four TX buffers of that size
  (256 KiB in all at 65536, instead of 64 KiB); it also raises the TSO limit and the TX queue length. Effects on
  other `r8152` chips are not known.
- The hotplug script below acts on every `r8152` network device. It reloads OpenWrt's packet steering, which re-applies
  CPU placement (RPS, NAPI threads) to all network devices, including Wi-Fi, and replaces manual settings. If
  packet steering is turned off (`network.@globals[0].packet_steering=0`), the reload keeps it off and RPS stays 0.

### 2a. Put the files in place before the build

1. The driver patch [usb-nic/798-net-usb-r8152-make-agg_buf_sz-a-module-parameter.patch](usb-nic/798-net-usb-r8152-make-agg_buf_sz-a-module-parameter.patch)
   makes the buffer size a read-only module parameter; without the parameter the driver behaves as before. It is not
   part of the fork, and why the upstream driver uses 16 KiB has not been looked into. Copy it to
   `local/kernel-patches/`:

       mkdir -p local/kernel-patches
       cp docs/usb-nic/798-net-usb-r8152-make-agg_buf_sz-a-module-parameter.patch local/kernel-patches/

2. The parameter, in `local/files/etc/modules.conf` (keep any lines you already have there):

       options r8152 agg_buf_sz=65536

   Parsed values outside 16384-65536 are replaced by 16384 with a warning in the kernel log; a value that is not a
   number makes the module fail to load.

3. The hotplug script [usb-nic/30-r8152-tune](usb-nic/30-r8152-tune) as `local/files/etc/hotplug.d/net/30-r8152-tune`:

       mkdir -p local/files/etc/hotplug.d/net
       cp docs/usb-nic/30-r8152-tune local/files/etc/hotplug.d/net/

   The files must be readable by others on your computer (see "Customizing the image" in the README).

### 2b. Build and install

    STAMP=$(./build.sh start --local-config --kernel-patches)

Then `status`, `collect` and install as in the README. `PROVENANCE` lists the patch under "kernel patches" and
the build class says `modified: local-config, kernel-patches, rootfs overlay`.

### 2c. Check on the unit

Find the adapter's interface name (it is often `eth1`, but use what this prints):

    for d in /sys/class/net/*; do
      [ "$(basename "$(readlink $d/device/driver)")" = r8152 ] && echo "${d##*/}"
    done

With `IF` set to that name and a cable connected:

| Check | Command | Expected |
|---|---|---|
| USB speed | `cat /sys/class/net/$IF/device/../speed` | `5000` |
| Link | `ip link set $IF up; cat /sys/class/net/$IF/speed` | `2500` |
| Buffer size | `cat /sys/module/r8152/parameters/agg_buf_sz` | `65536`; no such file: the running module is not the patched one |
| Threaded NAPI | `cat /sys/class/net/$IF/threaded` | `1` |
| RPS | `cat /sys/class/net/$IF/queues/rx-0/rps_cpus` | not `0` when packet steering is on |
| Hotplug script | `logread -e r8152-tune` | a line per adapter; a `failed:` line names what failed. At boot the line can be missing because the log service starts later. |

These show the settings, not that the network works: after you give the adapter its place in your network (below),
check that the unit is reachable through it, and run a short transfer if you want a speed figure.

If a check fails, do not move your uplink to the adapter yet:
- no `agg_buf_sz` file: the image was built without `--kernel-patches`, or another `r8152` module is loaded;
- `agg_buf_sz` is 16384: `/etc/modules.conf` has no valid `options r8152` line, or the module was loaded before it
  was there;
- `threaded` is 0 or RPS is 0: see the `r8152-tune` line in the log; with packet steering off, RPS 0 is expected.

Changing these on a unit that already runs: `/etc/modules.conf` takes effect the next time the module is loaded by
OpenWrt's module loader (in practice, a reboot; `insmod r8152` by hand does not read it), and the hotplug script runs
the next time the adapter appears (replug or reboot). Do not unload
the driver of the adapter you manage the unit through.

## 3. Using the adapter in your network

Installing the driver does not add the adapter to any network: it is an unconfigured interface until you add it.
Keep a working management path (for example a LAN jack, or Wi-Fi) while you change this, and change one thing at a
time.

- **As the uplink of an access point (bridged):** add the adapter to the bridge or VLAN that the current uplink jack is
  in, and remove that jack from it in the same change, then move the cable from the jack to the adapter. A bridge
  without STP (OpenWrt's default) must not have two ports connected to the same network: that makes a loop.
- **As the WAN of a router:** the image's defaults have `wan` as its own interface, not in the LAN bridge. Make the
  adapter the device of the WAN interface (`network.wan.device`, and `wan6` if used) instead of the `wan` jack.

The interface name of the adapter can change if more than one USB network adapter is plugged in.
