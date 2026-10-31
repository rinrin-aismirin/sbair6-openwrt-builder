# Keys and failsafe mode

This page describes what the RESET, WPS and LEVEL keys do on OpenWrt: failsafe mode with WPS or RESET, switching
slots with LEVEL, and RESET after start-up. The steps for an unreachable unit are in
[When you cannot reach the unit](../recovery.md); read the
[overview](README.md#overview) first for the slots.

## The keys

| Key | Where | In the device tree | Early in start-up | After start-up |
| --- | --- | --- | --- | --- |
| WPS | Back | `WPS_KEY`, GPIO 1, `KEY_WPS_BUTTON` | Enters failsafe mode | - |
| RESET | Bottom (hole) | `RESET_KEY`, GPIO 29, `KEY_RESTART` | Enters failsafe mode | Reboot or factory reset ([below](#reset-after-start-up)) |
| LEVEL | Front | `LEVEL_KEY`, GPIO 28, `BTN_0` | Held from power-on: switches slots | - |

All three are active low and polled by the kernel every 20 ms with a 60 ms debounce, so quick taps can be missed.
What WPS and LEVEL do after start-up depends on the packages in the image; the Air 6 tools add nothing there.

## What start-up does with the keys

OpenWrt reads the keys in its early start-up (preinit), about 15-20 seconds after the power is plugged in. In order:

1. `/lib/preinit/06_air6_preinit_iface` sets the failsafe network port to `lan` (jack 1). The MediaTek default names a
   port `lan1`, which the Air 6 does not have.
2. `/lib/preinit/25_air6_slot_switch` checks whether LEVEL is held
   ([switching slots](#switching-slots-with-the-level-key)). When it is not, it adds no delay.
3. `/lib/preinit/29_air6_failsafe_keys` starts reading WPS and RESET.
4. OpenWrt's failsafe wait runs for 4 seconds. A key press, or `f` and Enter on the serial console, enters failsafe
   mode.
5. `/lib/preinit/31_air6_failsafe_keys` stops the reading of the keys; then start-up continues in failsafe mode or
   normally.

Steps 3 and 5 exist because key events on this board reach OpenWrt's failsafe handler only after the kernel's random
number generator is ready. On the tested unit that was 10-19 seconds after the kernel started, while the wait ended
about 8 seconds after the kernel started. The Air 6 hooks therefore read the keys' GPIO levels directly (through
debugfs) during the whole wait. A key counts as pressed when two readings in a row show it pressed; its name then goes
to `/tmp/failsafe_button`, which the failsafe wait checks when it ends.

## Failsafe mode

Failsafe mode is OpenWrt's: it starts the same OpenWrt without your settings, with 192.168.1.1/24 on jack 1 and root
login without a password (OpenWrt's
[failsafe guide](https://openwrt.org/docs/guide-user/troubleshooting/failsafe_and_factory_reset)).
It writes nothing to the boot control bytes: the end-of-start-up step that marks a slot good and resets its retry
count does not run in failsafe mode ([boot control](boot-control.md#marking-a-slot-good)).

**Repeated failsafe sessions can switch slots.** `reboot -f` is a warm reboot, and the bootloader counts it. After
about four failsafe sessions in a row without a normal start-up in between, the count reaches the bootloader's limit
and the unit starts the other slot ([boot control](boot-control.md#how-the-bootloader-uses-them)). This is read from
the code and the bootloader's rule; it has not been tried.

**Entering it with a key.** One press of WPS or RESET inside the 4-second wait is enough. Because the wait starts
about 15-20 seconds after the power is plugged in and is not shown on the unit, the instructions are to press WPS
slowly, about once a second (holding each press for a moment), for about 30 seconds after plugging in
([failsafe mode with the WPS key](../recovery.md#its-settings-are-the-problem-failsafe-mode-with-the-wps-key)).

**Use WPS, not RESET.** A RESET press that misses the wait reaches normal OpenWrt, where it reboots the unit or, held
5 seconds or more, erases your settings ([RESET after start-up](#reset-after-start-up)).

**LEVEL is not a failsafe key.** When LEVEL triggers OpenWrt's failsafe handler, the Air 6 hooks drop that trigger:
`25_air6_slot_switch` after a LEVEL hold, and `29_air6_failsafe_keys` at every reading while no other key is pressed.
A WPS or RESET trigger that arrives at the same moment is kept. Two narrow cases remain:

- A LEVEL event that arrives after the last reading and before the failsafe wait reads its file still enters failsafe
  mode; the gap is a few shell statements long.
- A WPS or RESET event that arrives late (describing an earlier press), after the wait has looked but before the last
  reading, also enters failsafe mode.

**Leaving it.** Run `reboot -f`. A WPS or RESET press during the next wait enters failsafe mode again, so release the
key first.

What was tried on the unit: [status](status.md#tested).

## Switching slots with the LEVEL key

Holding the front LEVEL key from power-on makes the other slot boot next and reboots into it. This is for a build that
starts but does not work. The other slot must be marked good.

1. At power-on with LEVEL held, `25_air6_slot_switch` (step 2 [above](#what-start-up-does-with-the-keys)) reads the
   key. The three blue signal LEDs light up and go out one by one, one per second. Releasing the key during this
   countdown cancels the switch; start-up continues normally.
2. It runs `air6-slot set-active` for the other slot ([choosing the next slot](boot-control.md#choosing-the-next-slot)):
   the other slot's retry count is set to 00 and it gets the higher priority. Nothing else is written.
3. When the key is released, the unit reboots (`reboot -f`) and the bootloader starts the other slot.

What the LEDs show and what to do (the LED table):
[switch slots with the LEVEL key](../recovery.md#the-build-itself-does-not-work-switch-slots-with-the-level-key).
Behind them:

- The blue LEDs blink while the key is held after the other slot was selected; releasing it reboots.
- The red signal LED blinks until the key is released when `set-active` refused before writing (exit code 3, 4 or 5;
  usually the other slot is not marked good), or when the running slot could not be read. Start-up then continues
  normally.

The red LED stays on when:

- the write of the selection failed (`set-active` exit code 6): which slot boots next is uncertain;
- the reboot command returned: the other slot stays selected for the next boot;
- the key was not released within 60 seconds after the selection: the hook selects the running slot again. When that
  works, the running slot boots next; when it is refused or fails, the console says so and the other slot (or an
  uncertain one) boots next;
- after a refusal, the key was not released within 60 seconds.

The hook reads the key from its GPIO level in debugfs rather than from key events, because the event of a key held at
power-on can be lost: the key driver loads before OpenWrt's early-start-up event listener starts.

What was tried on the unit: [status](status.md#tested).

## RESET after start-up

Once OpenWrt has started normally, RESET is handled by OpenWrt's standard handler (`/etc/rc.button/reset`):

| Press | Effect |
| --- | --- |
| Released within 1 second | Reboot |
| 1 to 4 seconds | Nothing |
| 5 seconds or more | Factory reset: erases the settings of the running slot, then reboots |

A short press rebooting the unit was seen on the unit. The factory reset has not been tried on the unit.
