#!/bin/bash

cpu_count() {
	grep 'model name' /proc/cpuinfo | wc -l
}

cpu_model() {
	grep 'model name' /proc/cpuinfo | head -1 | sed -e 's/model name.*://'
}

get_rx_bytes() {
	grep $1 /proc/net/dev | tr ':' ' ' | awk '{print $2}'
}

get_rx_pkts() {
	grep $1 /proc/net/dev | tr ':' ' ' | awk '{print $3}'
}

main() {
	if ! [ -n "$(which lspci)" ]; then
		yum -y install pciutils
	fi
	clear
	echo h3. Используемый процессор
	echo $(cpu_count) x $(cpu_model)
	echo
	echo h3. Сетевые карты:
	lspci | grep Ethernet | sed -e 's/.*Ethernet controller: //' | sort -u | sed 's/^/* /g'
	echo

	for dev in $(brctl show | grep -o eth[0-9]); do
		rx1=$(get_rx_bytes $dev)
		rxp1=$(get_rx_pkts $dev)
		sleep 1
		rx2=$(get_rx_bytes $dev)
		rxp2=$(get_rx_pkts $dev)
		delta=$((rx2-rx1))
		delta_pkts=$((rxp2-rxp1))
		if [ $delta = 0 -o $delta_pkts = 0 ]; then
			continue
		fi
		echo "h4. $dev (прерывания/буферы/usecs/объёмы трафика)"
		echo
		grep $dev /proc/interrupts
		echo $(ethtool -g $dev | egrep "RX:|set")
		ethtool -c $dev | grep "rx-usecs:"

		mirror_dev="$mirror_dev $dev"
		if [ "$((delta/1024/128)))" != 0 ]; then
			echo ≈$((delta/1024/128)) mbit/sec $delta_pkts pkts/sec
		elif [ "$((delta / 128)))" != 0 ]; then
			echo ≈$((delta/128)) kbit/sec $delta_pkts pkts/sec
		fi
		echo
	done
}

main
