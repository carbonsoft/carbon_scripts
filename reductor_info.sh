#!/bin/bash

cpu_count() {
	grep 'model name' /proc/cpuinfo | wc -l
}

cpu_model() {
	grep 'model name' /proc/cpuinfo | head -1 | sed -e 's/model name.*://'
}

get_rx_bytes() {
	grep $1 /proc/net/dev | tr -d ':' | awk '{print $2}'
}

main() {
	if ! [ -n "$(which lspci)" ]; then
		yum -y install pciutils
	fi
	clear
	echo Используемый процессор: $(cpu_count) x $(cpu_model)
	echo Сетевые карты:
	echo '{code}'
	lspci | grep Ethernet | sed -e 's/.*Ethernet controller: //'
	echo '{code}'
	echo Объём трафика в зеркале:
	for dev in $(brctl show | grep -o eth[0-9]); do
		rx1=$(get_rx_bytes $dev)
		sleep 1
		rx2=$(get_rx_bytes $dev)
		delta=$((rx2-rx1))
		echo $dev: ≈$((delta/1024/1024)) mb/sec
	done
}

main
