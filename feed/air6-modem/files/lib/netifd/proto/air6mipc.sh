#!/bin/sh
# netifd protocol for the SoftBank Air 6 modem (MIPC through the stock mipc_wan_cli, see air6-modem).

[ -n "$INCLUDE_ONLY" ] || {
	. /lib/functions.sh
	. /usr/share/libubox/jshn.sh
	. ../netifd-proto.sh
	init_proto "$@"
}

RUNTIME=/usr/libexec/air6-modem/runtime

proto_air6mipc_init_config() {
	available=1
	no_device=1
	proto_config_add_string apn
	proto_config_add_string auth
	proto_config_add_string username
	proto_config_add_string password
	proto_config_add_string pdptype
	proto_config_add_int mtu
	proto_config_add_boolean roaming
	proto_config_add_int delay
	proto_config_add_defaults
}

air6mipc_cli() { $RUNTIME cli "$@"; }

# Succeeds if the modem still holds a data call on DEVICE with an address (data_call_get prints one JSON object
# per call).
air6mipc_call_alive() {
	local dev=$1 l n
	air6mipc_cli 15 --data_call_get | grep '"iface"' | while read -r l; do
		[ "$(jsonfilter -s "$l" -e '@.iface')" = "$dev" ] || continue
		n=$(( $(jsonfilter -s "$l" -e '@.v4_count' || echo 0) + $(jsonfilter -s "$l" -e '@.v6_count' || echo 0) ))
		[ "$n" -gt 0 ] && echo alive
	done | grep -q alive
}

# How long a new call has to stay before it is used. After a change of the attach APN (check_ia re-attaching,
# as on the first call after the stock firmware ran) the modem can drop the new call again within about a second.
AIR6MIPC_SETTLE=3
air6mipc_now() { cut -d. -f1 /proc/uptime; }
air6mipc_deadline() { air6mipc_end=$(( $(air6mipc_now) + $1 )); }
air6mipc_expired() { [ "$(air6mipc_now)" -ge "$air6mipc_end" ]; }

proto_air6mipc_setup() {
	local interface="$1"
	local apn auth username password pdptype mtu roaming delay $PROTO_DEFAULT_OPTIONS
	json_get_vars apn auth username password pdptype mtu roaming delay $PROTO_DEFAULT_OPTIONS
	local authnum iptype roamnum sim nw result ifname dmtu air6mipc_end attempt
	local v4_addr v4_mask v4_gw v4_dns1 v4_dns2 v4_mtu v6_addr v6_gw v6_dns1 v6_dns2 v6_mtu

	[ -n "$apn" ] || { proto_notify_error "$interface" NO_APN; proto_block_restart "$interface"; return 1; }
	case "${auth:-none}" in
		none) authnum=0 ;; pap) authnum=1 ;; chap) authnum=2 ;; both) authnum=3 ;;
		*) proto_notify_error "$interface" INVALID_AUTH; proto_block_restart "$interface"; return 1 ;;
	esac
	case "${pdptype:-ipv4v6}" in
		ipv4|ip) iptype=1 ;; ipv6) iptype=2 ;; ipv4v6) iptype=3 ;;
		*) proto_notify_error "$interface" INVALID_PDPTYPE; proto_block_restart "$interface"; return 1 ;;
	esac
	# roaming_type is the PDP type while roaming (same as at home); the last check_ia argument allows roaming.
	roamnum=$iptype
	delay=${delay:-30}

	# Each wait below gets its own deadline of "delay" seconds of wall time.
	# Modem service up and the modem READY (md1:4), AT socket present.
	air6mipc_deadline "$delay"
	until grep -q '^md1:4 ' /sys/kernel/ccci/boot 2>/dev/null && [ -S /dev/adb_atci_socket ]; do
		air6mipc_expired && { proto_notify_error "$interface" MODEM_NOT_READY; return 1; }
		sleep 1
	done

	# SIM slot (the modem keeps whatever the stock firmware chose last), attach APN and radio on, then wait for
	# the SIM and the registration.
	$RUNTIME sim-select || { proto_notify_error "$interface" SIM_SLOT_FAILED; return 1; }
	air6mipc_cli 60 --check_ia "$apn" 21 "$iptype" "$roamnum" "$username" "$password" "$authnum" 0xfffdffff \
		"${roaming:-0}" > /dev/null
	air6mipc_deadline "$delay"
	while :; do
		sim=$(air6mipc_cli 10 --show_sim_status)
		case "$sim" in
			MIPC_SIM_STATUS_COMPLETE_READY) break ;;
			MIPC_SIM_STATUS_NOT_INSERT) proto_notify_error "$interface" SIM_NOT_INSERTED
				proto_block_restart "$interface"; return 1 ;;
			MIPC_SIM_STATUS_SIM_PIN|MIPC_SIM_STATUS_SIM_PUK) proto_notify_error "$interface" SIM_LOCKED
				proto_block_restart "$interface"; return 1 ;;
		esac
		air6mipc_expired && { proto_notify_error "$interface" SIM_NOT_READY; return 1; }
		sleep 2
	done
	air6mipc_deadline "$delay"
	while :; do
		# +CEREG/+C5GREG: <n>,<stat>; stat 1 = home, 5 = roaming.
		nw=$(air6mipc_cli 10 --at_cmd 'AT+CEREG?'; air6mipc_cli 10 --at_cmd 'AT+C5GREG?')
		echo "$nw" | grep -q '^+C[E5]G\?REG: *[0-9]*,1' && break
		[ "${roaming:-0}" = 1 ] && echo "$nw" | grep -q '^+C[E5]G\?REG: *[0-9]*,5' && break
		air6mipc_expired && { proto_notify_error "$interface" NOT_REGISTERED; return 1; }
		sleep 2
	done

	# The call, checked after it settled; a call the modem dropped meanwhile is made once more.
	for attempt in 1 2; do
		air6mipc_cli 20 --data_call_deact_apn "$apn" > /dev/null
		json_init
		json_add_string apn "$apn"
		json_add_int ip_type "$iptype"
		json_add_int roaming_type "$roamnum"
		json_add_int auth_type "$authnum"
		json_add_string username "$username"
		json_add_string password "$password"
		json_add_string bearer_bitmask 0xfffdffff
		json_add_int mtu "${mtu:-1500}"
		json_add_int mode 1
		result=$(air6mipc_cli 90 --data_call_act "$(json_dump)" | grep '"result"')
		json_cleanup
		[ -n "$result" ] && json_load "$result" || { proto_notify_error "$interface" CALL_FAILED; return 1; }
		result= ifname= v4_addr= v6_addr=
		json_get_vars result ifname v4_addr v4_mask v4_gw v4_dns1 v4_dns2 v4_mtu v6_addr v6_gw v6_dns1 v6_dns2 v6_mtu
		# The network may grant fewer address families than requested (ipv4v6 answered with IPv4 only); a call
		# is usable when it carries at least one requested family.
		[ "$iptype" = 2 ] && v4_addr=
		[ "$iptype" = 1 ] && v6_addr=
		[ "$result" = 0 ] && [ -n "$ifname" ] && [ -n "$v4_addr$v6_addr" ] || {
			proto_notify_error "$interface" CALL_FAILED
			return 1
		}
		sleep "$AIR6MIPC_SETTLE"
		air6mipc_call_alive "$ifname" && break
		logger -t air6mipc "$interface: the modem dropped the data call on $ifname (attempt $attempt)"
		[ "$attempt" = 2 ] && { proto_notify_error "$interface" CALL_FAILED; return 1; }
	done
	if [ -n "$v4_addr" ]; then dmtu=$v4_mtu; else dmtu=$v6_mtu; fi

	ip link set dev "$ifname" mtu "${mtu:-${dmtu:-1500}}" up
	proto_init_update "$ifname" 1
	if [ -n "$v4_addr" ]; then
		proto_add_ipv4_address "$v4_addr" "${v4_mask:-32}"
		[ "$defaultroute" = 0 ] || proto_add_ipv4_route 0.0.0.0 0 "$v4_gw" "" "$metric"
		[ "$peerdns" = 0 ] || {
			[ -n "$v4_dns1" ] && proto_add_dns_server "$v4_dns1"
			[ -n "$v4_dns2" ] && proto_add_dns_server "$v4_dns2"
		}
	fi
	# IPv6 as the stock firmware applies it: the address the modem reports (/128) and a default route via the
	# reported gateway, or on-link through the point-to-point ccmni device when none is given. No prefix is
	# delegated to other interfaces. Untested: no SIM with IPv6 was available.
	if [ -n "$v6_addr" ]; then
		proto_add_ipv6_address "$v6_addr" 128
		[ "$defaultroute" = 0 ] || proto_add_ipv6_route :: 0 "$v6_gw" "$metric"
		[ "$peerdns" = 0 ] || {
			[ -n "$v6_dns1" ] && proto_add_dns_server "$v6_dns1"
			[ -n "$v6_dns2" ] && proto_add_dns_server "$v6_dns2"
		}
	fi
	proto_add_data
	json_add_string apn "$apn"
	json_add_string device "$ifname"
	proto_close_data
	proto_send_update "$interface"

	# Bringing the device up can also end with the call dropped. A down update alone leaves netifd waiting;
	# report the setup as failed so that it tears the interface down and sets it up again.
	sleep "$AIR6MIPC_SETTLE"
	air6mipc_call_alive "$ifname" || {
		logger -t air6mipc "$interface: the modem dropped the data call on $ifname after it was set up"
		proto_notify_error "$interface" CALL_FAILED
		proto_setup_failed "$interface"
		return 1
	}
}

proto_air6mipc_teardown() {
	local interface="$1" apn
	json_get_vars apn
	[ -n "$apn" ] && air6mipc_cli 20 --data_call_deact_apn "$apn" > /dev/null
	proto_init_update "*" 0
	proto_send_update "$interface"
}

[ -n "$INCLUDE_ONLY" ] || add_protocol air6mipc
