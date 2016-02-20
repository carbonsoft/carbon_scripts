#!/bin/bash

. /usr/local/Reductor/etc/const

ip_regex="([0-9]{1,3}\.){3}[0-9]{1,3}"
TMPDIR=${TMPDIR:-/tmp}
TMPFILE=$TMPDIR/hwinfo.tmp
LSPCI=$TMPDIR/lspci.tmp

add_lspci() {
	if [ ! -x /sbin/lspci ]; then
		yum -y install pciutils
	fi
}

grab_data() {
	for interface in /sys/class/net/*/brport/bridge; do
		if [ "$interface" = '/sys/class/net/*/brport/bridge' ]; then
			break
		fi
		bridge="$(readlink $interface | cut -d / -f3)"
		eth="$(cut -d / -f5 <<< $interface)"
		echo ${bridge#br} $eth
	done | sort -n | sed 's/^/br/' > $TMPFILE
	lspci > $LSPCI
}

if_ip() {
	ip -4 a show $1 | egrep -o $ip_regex/[0-9]+
}

bridges() {
	echo
	echo "# bridges"
	echo
	for bridge in $(cut -d ' ' -f1 $TMPFILE | uniq); do
		echo $bridge "$(if_ip $bridge)"
		for interface in $(grep -w $bridge $TMPFILE | cut -d ' ' -f2); do
			echo "- $interface $(if_ip $interface)"
		done
	done
}

devices() {
	echo
	echo "# devices"
	echo
	for eth in $(ip link | egrep -o eth[0-9]+ | sort -u); do
		for id in $(ethtool -i $eth | grep bus-info | sed 's/.*0000://'); do
			rx_buf="$(ethtool -g $eth | tac | grep RX: | egrep -o [0-9]+ | tr '\n' '/'| sed 's|/$||g')"
			echo "$eth: $(grep -w $id $LSPCI) rx: $rx_buf"
		done
	done 
}

_uptime() {
	echo
	echo "# uptime"
	echo
	uptime
}

cpu() {
	echo
	echo "# cpu"
	echo
	egrep '(processor|model name)' /proc/cpuinfo | tail -2
}

interrupts() {
	echo
	echo "# interrupts"
	echo
	grep eth /proc/interrupts
}

config() {
	echo
	echo "# config"
	echo
	local useless='^(proc|monitoring|misc.diagnostic|reductorupdate.autoupdate_critical)'
	egrep "'[01]'" $CONFIG | tr -d "']" | tr '[' '.' | sed 's/=/ = /g' | sort -u | egrep -v "$useless"
}

main() {
	add_lspci
	grab_data
	bridges
	devices
	_uptime
	cpu
	interrupts
	config
}

main | sed -e 's/^[^#$]/    &/g'
