# When you cannot reach the unit

Use this page when the unit runs, or should run, OpenWrt but `ssh root@192.168.1.1` or http://192.168.1.1 does not
answer, at any stage. Work through the sections in order: check the connection first, then wait for a trial image,
then use the keys. For a command that stopped with an error, see [troubleshooting](troubleshooting.md) instead.

In the commands, `root@DEVICE` is the unit while it runs the stock firmware (its address on your network), and
`root@192.168.1.1` is the unit while it runs OpenWrt, reached from a computer on jack 1.

## Check the connection first

- OpenWrt took about 70 seconds to answer in our tests. Wait at least that long after the reboot.
- The computer must be on jack 1. With OpenWrt's defaults it should get an address in 192.168.1.0/24 (these defaults
  have not been tried on a unit yet). If it is also connected to another network that uses 192.168.1.0/24,
  disconnect that network.
- ssh refuses with a changed host key warning: OpenWrt has new SSH host keys. Run `ssh-keygen -R 192.168.1.1` and
  connect again.
- If your settings (kept from an earlier slot, or set through `local/files`) change the LAN address, the unit is at
  that address instead of 192.168.1.1.

These are the same preparations as in [step 4 of docs/1-try.md](1-try.md#4-reboot-and-connect).

## A trial image that is not kept: wait

If its timer was armed, it returns to the other slot about 10 minutes after start-up. Whether the timer was armed
cannot be checked when you cannot reach the unit. If nothing happens within 15 minutes, use one of the ways below.

## The unit is back on the other slot

If `./device.sh status root@DEVICE` answers on the stock firmware's address after an install, OpenWrt did not start
(or, with a trial image, was not kept in time). The stock firmware and its slot are unchanged; you can try again from
[step 3 of docs/1-try.md](1-try.md#3-install).

After an update, the unit returns to the previous OpenWrt instead, at the same address: run `./device.sh
upgrade-check` ([upgrade-check does not say written](troubleshooting.md#upgrade-check-does-not-say-written)).

## Its settings are the problem: failsafe mode with the WPS key

Failsafe mode starts the same OpenWrt without your settings, at 192.168.1.1 on jack 1, with no password.

1. Unplug the power and plug it back in.
2. Press the WPS key on the back slowly, about once a second (hold each press for a moment), for about 30 seconds.
   OpenWrt waits for a key for 4 seconds early in start-up, about 15-20 seconds after the power is plugged in; one
   press inside that wait is enough. Quick taps can be missed.
3. Log in with `ssh root@192.168.1.1` from the computer on jack 1, fix or reset the settings (OpenWrt's
   [failsafe guide](https://openwrt.org/docs/guide-user/troubleshooting/failsafe_and_factory_reset)), and leave
   failsafe mode with `reboot -f`.

`reboot -f` is a warm reboot, and the bootloader counts it: about four failsafe sessions in a row without a normal
start-up in between can reach its limit and start the other slot (read from the code; not tried;
[details](reference/keys-and-failsafe.md#failsafe-mode)).

Use WPS rather than RESET: a RESET press that misses the wait reaches normal OpenWrt, where a short press reboots and
a press of 5 seconds or more erases your settings. The front LEVEL key is for switching slots, not for failsafe mode.

Tried on one unit: failsafe mode entered with WPS (192.168.1.1 set on jack 1, left with `reboot -f` over the serial
console); with RESET only on an earlier build, before later fixes to the key handling. Logging in over the network
was not tried ([status](reference/status.md#tested)).

## The build itself does not work: switch slots with the LEVEL key

Unplug the power, hold the front LEVEL key, and plug the power back in while holding it. Keep holding: the blue LEDs
start the countdown about 15-20 seconds after the power is plugged in.

| What you see | What it means | What to do |
| --- | --- | --- |
| The three blue signal LEDs light up and go out one by one (3 seconds) | Counting down | Keep holding; release now to cancel |
| The blue LEDs blink | The other slot is selected | Release the key: the unit reboots into the other slot |
| The red signal LED blinks | The switch was refused before anything was written (usually: the other slot is not marked good), or the running slot could not be determined | Release the key: the unit starts normally |
| The red signal LED stays on | Something did not go as planned: the selection could not be written, the reboot failed, or the key was held too long; the next boot slot may be either one (the serial console says which) | Release the key; once the unit is up, check `air6-slot status` |
| You hold the key for more than 60 seconds after the count | The switch is undone where possible; red LED on (the serial console says if the undo was refused or failed) | Release the key |

What was tried on the unit: [status](reference/status.md#tested). The red-LED and 60-second cases were not tried.

Nothing returns by itself from an image that hangs before start-up finishes without the unit resetting, and pulling
the power does not count as a failed attempt, so power cycling does not bring the other slot back. The LEVEL key is
then the way out, if start-up gets as far as reading the key. How the keys work:
[docs/reference/keys-and-failsafe.md](reference/keys-and-failsafe.md).
