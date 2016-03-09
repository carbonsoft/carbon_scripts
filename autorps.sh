#!/bin/bash

set -eu

if [ "$#" -lt 1 -o "$@" == '--help' -o "$@" == '-h' ]; then
   echo "Usage: $0 <device>"
   echo "Example: $0 eth2"
   exit 1
fi

queue_count="$(find /sys/class/net/$dev/queues/ -type d -name "rx-*" | wc -l)"
cpu_count="$(grep -c 'model name' /proc/cpuinfo)"
if [ "$queue_count" == '1' -a "$cpu_count" -gt 1 ]; then
	printf "%x\n" $((2**$cpu_count - 1)) > /sys/class/net/$dev/queues/rx-0/rps_cpus
fi
