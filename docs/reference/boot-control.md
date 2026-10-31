# Boot control

This page describes how the unit chooses the slot it boots, how OpenWrt marks a slot good, how trial images return,
and the `air6-slot` command. Read the [overview](README.md#overview) first.

- [The boot control bytes](#the-boot-control-bytes)
- [How the bootloader uses them](#how-the-bootloader-uses-them)
- [Marking a slot good](#marking-a-slot-good)
- [Trial images](#trial-images)
- [Choosing the next slot](#choosing-the-next-slot)
- [Who writes the bytes](#who-writes-the-bytes)
- [How the bytes are written](#how-the-bytes-are-written)
- [Reading the status](#reading-the-status)
- [Failed-update records](#failed-update-records)
- [Files on the unit](#files-on-the-unit)

## The boot control bytes

The bootloader chooses the slot from a 10-byte record in the shared `misc` partition, at byte offset 2060. The magic
`BCAB` at offset 2052 marks it. The layout comes from the stock firmware's `/lib/upgrade/bootctrl.sh`.

| Byte | Slot A | Byte | Slot B | Values |
| --- | --- | --- | --- | --- |
| 0 | priority | 5 | priority | `0f` boots next, `0e` does not |
| 1 | retry count | 6 | retry count | see [the bootloader](#how-the-bootloader-uses-them) |
| 2 | success flag | 7 | success flag | `01` marked good, `00` not |
| 3 | update type | 8 | update type | a stock firmware field; the OpenWrt tools never change it |
| 4 | unused | 9 | unused | |

The tools show the record as 20 hex digits (`bootctrl=` on the stock firmware, the `slot a:` and `slot b:` lines in
`air6-slot status`). Examples:

| Bytes | Meaning |
| --- | --- |
| `0f000101000e00010100` | Slot A boots next and is marked good; slot B is marked good. A stock firmware on slot A before an install looks like this |
| `0e000101000f02000100` | After an install from slot A: slot B boots next, retry 02, not marked good |
| `0f020001000e00010100` | After an install from slot B: slot A boots next, retry 02, not marked good |

## How the bootloader uses them

- It boots the slot with priority `0f`.
- It increments that slot's retry count at every warm boot. Pulling the power does not count.
- When the count of the slot it is about to boot has reached 4, it starts the other slot instead. An install,
  `switch`, update or restore presets the new slot's count to 02. After warm reboots the switch was seen at 4
  (2026-10-31: a trial image after an update booted with 03, then 04, and the third warm boot started the other
  slot). A normal start-up in between marks the slot good and resets its count.
- After crashes, the number and length of the attempts are less certain:
  - In the one crash test (2026-10-17: a root file system erased by a test script, the count starting at 00), each
    attempt panicked and the unit reset after about 30 seconds; the other slot started about 2 minutes after the
    reboot (three or four attempts).
  - During a chain of abnormal resets (2026-10-25, reboots started from the bootloader's serial shell), the
    bootloader read 4 and 5, logged `skip switch for abnormal` and did not switch; it switched at 6, at the next
    reset that was not abnormal.
  - A crash with the count preset to 02 (after an install or update) has not been tried.
- The bootloader does not look at the success flag for this: a slot marked good would also be given up after enough
  warm reboots if nothing reset its count. OpenWrt resets its own slot's count at the end of a normal start-up
  ([below](#marking-a-slot-good)); the stock firmware does the same for its slot. Failsafe boots and boots with a
  wrong `root=` do not reset it, so their warm reboots add up.
- It was seen refusing to switch to a slot whose own count was 06. OpenWrt therefore resets the other slot's count
  to 00 when it is above 3 (same rule as the stock firmware), and `set-active` resets the count of the slot it
  selects.
- It replaces `root=/dev/mmcblk0p24` on the kernel command line with the root partition of the booted slot (p26 on
  slot A, p39 on slot B; see [partitions](partitions.md)). The image's device tree therefore carries
  `root=/dev/mmcblk0p24`, and `CHECK.txt` checks it ([build](../build.md)). An image with any other `root=` would
  boot the same root file system from both slots.

## Marking a slot good

At the end of every normal start-up (init script `/etc/init.d/air6-slot`, START=99), `air6-slot boot-done` reads the
record and, in one write:

1. records a failed update when the other slot is not marked good and its count is 4 or more
   ([failed-update records](#failed-update-records));
2. resets the other slot's count to 00 when it is above 3; its priority is not changed;
3. marks the booted slot good with count 00 (`success=01`, `retry=00`), except:
   - for a trial image whose slot is not marked good yet: the slot is left as it is
     ([trial images](#trial-images));
   - when the root file system is not the booted slot's root partition: the slot is not marked good and its count
     is not reset; the error goes to the system log and to `air6-slot status` (`WARNING: ...`). When the check
     cannot decide (`root=unknown`), the slot is marked good.

`boot-done` is not a health check: a slot is marked good when start-up finishes, whether the network works or not.
It does not run in failsafe mode, so a failsafe boot leaves the record as the bootloader left it: the slot's count
stays as the bootloader incremented it. Repeated failsafe sessions left with `reboot -f` (a warm reboot) without a
normal start-up in between can therefore reach the limit, and the bootloader then starts the other slot (read from
the code; not tried). Running `boot-done` again is safe.

## Trial images

A trial image is not marked good at the end of start-up. Unless you keep it, it returns to the other slot about 10
minutes after start-up, when its timer is armed (below). You choose this when you build: `./build.sh start --trial` adds
`air6.trial=1` to the kernel command line in the image's device tree. The policy belongs to the image: it is
read-only and is not carried over by settings or a config backup. `air6-slot status` shows it as `policy=trial` or
`policy=normal`.

**Arming.** Early in start-up (init script `/etc/init.d/air6-slot-trial`, START=11), `air6-slot trial arm` starts a
600-second timer when all of these hold:

- the image is a trial image;
- the booted slot is not marked good;
- the other slot is marked good (there is a slot to return to);
- the booted slot boots next.

Otherwise it records why there is no timer (`timer=` values below). There is one timer per boot; running `trial arm`
again neither adds one nor extends it. The timer state lives in `/tmp` and ends with the boot: a trial image that is
rebooted before it is kept arms a new timer, and the bootloader counts that reboot
([above](#how-the-bootloader-uses-them)).

The 600 seconds count from the arming, early in start-up, not from the reboot. The stage pages therefore tell you to
keep an image within 10 minutes of the reboot: that is always before the deadline.

**Keeping it.** `air6-slot trial commit` (from the kit computer: `./device.sh trial-commit`) marks the booted slot
good with count 00 and ends the timer. It is refused when the image is not a trial image, when the timer has already
fired, or when the booted slot no longer boots next. From then on the image behaves like a normal one.

**Expiry.** When the time is up, the timer checks the record under the lock. If the booted slot was marked good or no
longer boots next, it does nothing. Otherwise it selects the other slot (the same bytes as `set-active`, but the
update reservation is not checked) and reboots. If the
lock is busy, it tries again every 5 seconds, up to 60 seconds after the deadline; the deadline is not extended. If it
cannot select the other slot, it does not reboot and logs why (`logread -e air6-slot`).

| `timer=` in `air6-slot status` | Meaning |
| --- | --- |
| `armed, returns to slot X in Ns` | The timer runs |
| `armed, due Ns ago` | The deadline has passed; the return is under way (the lock is being retried) |
| `committed` | Kept, or the slot was already marked good at this boot; no return |
| `cancelled` | A slot was chosen by hand (`set-active`), or at the deadline the booted slot was already marked good or no longer booted next; no return |
| `fired` | The other slot is selected; a reboot follows |
| `no-fallback` | The other slot is not marked good; no return |
| `not-armed` | The booted slot does not boot next; no return |
| `error` | The record could not be read or written; no return |
| `overdue` | More than 60 seconds past the deadline and no return happened; it is no longer retried |
| `none` | No timer state in this boot; no return |

## Choosing the next slot

`air6-slot set-active SLOT` (from the kit computer: `./device.sh set-active DEVICE SLOT`) makes `SLOT` boot next. It
does not reboot.

- The slot must be marked good; otherwise it is refused ("not marked successful") and nothing changes. A slot that
  sysupgrade or a restore writes is marked not good before the first write and stays so until it has started and
  finished start-up (a trial image: until `trial commit`), so it cannot be selected in between.
- For the other slot, it sets that slot's count to 00 and the priorities; for the booted slot, only the priorities
  (this undoes a selection that has not been rebooted into yet).
- It is refused while a backup, restore or update of the other slot runs ("an update of the other slot is in
  progress", [below](#how-the-bytes-are-written)).
- It ends a pending trial timer (`timer=cancelled`).

The LEVEL key at power-on runs the same command ([LEVEL key](keys-and-failsafe.md#switching-slots-with-the-level-key)).

## Who writes the bytes

| Writer | Runs on | What it writes |
| --- | --- | --- |
| `./device.sh install`, `./device.sh switch` | Stock firmware | The stock firmware's `change_slot_info`, then the new slot's count set to 02: new slot priority `0f`, count 02, not marked good; running slot priority `0e`. Prints a `rollback` command with the previous bytes |
| Stock firmware, end of its start-up | Stock firmware | Marks its own slot good (seen after a restore of the stock firmware) |
| Stock firmware, its own update | Stock firmware | Writes the slot it is not running from and selects it (read from the stock update script; not observed) |
| `air6-slot boot-done` | OpenWrt, START=99 | [Marking a slot good](#marking-a-slot-good) |
| `air6-slot trial arm` and the timer | OpenWrt, START=11 | At expiry, the same bytes as `set-active` to the other slot (the update reservation is not checked) |
| `air6-slot trial commit` | OpenWrt | The booted slot marked good, count 00 |
| `air6-slot set-active` | OpenWrt; the LEVEL key | [Choosing the next slot](#choosing-the-next-slot) |
| sysupgrade, `air6-stock restore` | OpenWrt | Before the first partition write, the other slot is marked not good. After every write has been read back: other slot priority `0f`, count 02, not marked good; running slot priority `0e`, its count and success flag unchanged ([sysupgrade](sysupgrade.md), [stock backup](stock-backup.md)) |

`./device.sh switch` writes the same bytes as an install without writing the slot: the slot starts like a fresh
install, and a trial image arms its timer again.

## How the bytes are written

On OpenWrt, every change goes through `/lib/air6/bootctrl.sh`:

- **Lock.** A short lock (`flock` on `/tmp/lock/air6-bootctrl.lock`) around read, decision and write. A command that
  does not get it within 10 attempts, 1 second apart, stops as busy.
- **Checks.** The record is refused as unexpected when a priority is not `0e`/`0f` or a success flag not `00`/`01`;
  nothing is written then.
- **One write, then read back.** The new record is written as one 10-byte write with `fsync`, then `sync`, then read
  back. "Verified" means that the read-back matched. The write is not claimed to be atomic against a power cut.
- **Update reservation.** sysupgrade and `air6-stock` (backup and restore) create `/tmp/air6-update` while they work
  on the other slot. While it exists, `set-active` is refused and `air6-slot status` shows `update in progress: ...`.
  It is in `/tmp`, so a reboot ends it.

Exit codes of `air6-slot` (and of the library functions):

| Code | Meaning |
| --- | --- |
| 0 | Done (also when the record already was in the requested state) |
| 2 | Usage error |
| 3 | Refused; nothing changed |
| 4 | Busy (lock or update reservation); nothing changed |
| 5 | Environment or read error; nothing changed |
| 6 | Failed after a write was started; read the state again with `air6-slot status` |

## Reading the status

`air6-slot status` on OpenWrt (from the kit computer: `./device.sh status DEVICE`) prints, for example:

    booted=b
    next=b
    slot a: prio=0e retry=00 success=01 uptype=01
    slot b: prio=0f retry=00 success=01 uptype=01
    root=rootfs_b
    policy=normal
    failed updates: none recorded

| Line | Meaning |
| --- | --- |
| `booted=` | The running slot, from `bootslot=` on the kernel command line |
| `next=` | The slot with priority `0f`; `unknown` when the priorities do not decide it |
| `slot a:`, `slot b:` | The record, per slot |
| `warning: unexpected boot control record` | A priority or success flag outside the expected values; the tools do not write such a record |
| `root=rootfs_X` | The root file system is the booted slot's root partition |
| `WARNING: ...` instead of `root=` | The image boots another slot's root file system; the slot is not marked good. Do not update from this state |
| `root=unknown` | The check could not decide |
| `update in progress: ...` | A backup, restore or update of the other slot runs, or was interrupted in this boot |
| `policy=`, `timer=` | [Trial images](#trial-images); `timer=` only for a trial image |
| `failed updates: ...` | [Failed-update records](#failed-update-records) |
| `last sysupgrade record ...` | The result of the last update ([sysupgrade](sysupgrade.md)) |

On the stock firmware, `./device.sh status DEVICE` prints the time, the running slot and the record in one line, for
example `00:03:51 bootslot=a uptime=959.17 bootctrl=0f000101000e00010100`, followed by the bootloader's boot-reason
lines.

## Failed-update records

When `boot-done` finds the other slot not marked good with a count of 4 or more, it records this before resetting the
count: a line in the system log and a line in `/etc/air6-slot/failed-events` (time, marked as possibly wrong because
the clock may not be set; boot ID; booted slot; the other slot's priority, count and flag). The last 10 lines are
kept; the same observation is not added twice in one boot. `air6-slot status` lists them under "failed updates".
Remove them with `rm /etc/air6-slot/failed-events`.

A record means "a slot that was not marked good reached the bootloader's retry limit". It does not prove that the
image was broken: an uncommitted trial image that is rebooted twice leaves the same record. The slot stays not marked
good after the reset, so neither `set-active` nor the LEVEL key selects it. If the record cannot be saved, the boot
control write still happens and the error is reported.

## Files on the unit

The paths under `/usr`, `/lib` and `/etc/init.d` come from the fork's `air6-tools` package
(`package/utils/air6-tools/`); the paths under `/tmp` and `/etc/air6-slot/` are created by the tools at run time.

| Path | Purpose |
| --- | --- |
| `/usr/sbin/air6-slot` | The command: `status`, `current`, `boot-done`, `set-active`, `trial arm`, `trial commit` |
| `/lib/air6/bootctrl.sh` | The record layout, the lock, the checked transitions, the update reservation |
| `/etc/init.d/air6-slot` | START=99: `air6-slot boot-done` |
| `/etc/init.d/air6-slot-trial` | START=11: `air6-slot trial arm` |
| `/lib/preinit/25_air6_slot_switch` | The LEVEL key at power-on ([keys](keys-and-failsafe.md)) |
| `/tmp/air6-slot/timer` | Trial timer state of this boot |
| `/tmp/lock/air6-bootctrl.lock` | The lock |
| `/tmp/air6-update` | The update reservation |
| `/etc/air6-slot/failed-events` | Failed-update records of this slot |
| `/etc/air6-slot/last-upgrade` | The last sysupgrade record ([sysupgrade](sysupgrade.md)) |
| `/etc/air6-slot/stock-backup-<slot>` | The confirmation of a stock backup ([stock backup](stock-backup.md)) |

`/etc/air6-slot/` is in the running slot's settings area; sysupgrade does not carry it to the new slot
([sysupgrade](sysupgrade.md#settings)).
