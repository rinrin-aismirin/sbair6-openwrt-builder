# Print the booted slot, the boot control bytes and the boot-reason lines. Stock firmware only; on OpenWrt
# use `air6-abguard status`. Run on the device over SSH:
#   ssh root@DEVICE 'sh -s' < scripts/device/read_ab.sh
# bootctrl is 10 bytes: slot A prio, retry, success, uptype, (unused), then the same for slot B.
. /lib/upgrade/common.sh 2>/dev/null; . /lib/upgrade/platform.sh 2>/dev/null; . /lib/upgrade/bootctrl.sh
FLASH_TYPE=$(get_flash_type)
echo "$(date +%T) $(grep -oE 'bootslot=[ab]' /proc/cmdline) uptime=$(cut -d' ' -f1 /proc/uptime) bootctrl=$(get_bootctrl_string)"
grep -E '\[RGU\] rst from|retry_flag|\[AB\] (Current|ab_suffix|switch)|QL_AB\]current|ab_switch|skip switch' /proc/pl_lk | head -8
