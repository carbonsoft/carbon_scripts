#!/bin/bash

. /usr/local/Reductor/etc/const

lookup() {
	for dns in $(grep nameserver $CHROOTDIR/etc/resolv.conf | egrep -o $ip_regex | sort -u); do
		timeout -s 15 1s chroot $CHROOTDIR nslookup "$1" "$dns" | grep -A 1000 ^Name | egrep -o "$ip_regex"
	done
}

url=$1

echo "# в http.load"
domain=$1
if [ "${1:0:7}" = 'http://' ]; then
	domain="$(echo $1 | cut -d '/' -f3)"
fi

with_www="$1"
without_www="$1"
if [ "${with_www:0:11}" != "http://www" ]; then
	with_www="${1/http:\/\//http:\/\/www.}"
fi

if [ "${without_www:0:11}" = "http://www" ]; then
	without_www="${1/http:\/\/www./http:\/\/}"
fi

if ! grep "$1" $LISTDIR/http.load; then
	echo "# в прочих списках"
	grep "$domain" $LISTDIR/*
fi

echo "# ip address"
for ip in $(lookup "$domain"); do
	grep -w $ip $LISTDIR/ip.load
done | sort -u | sed -e 's/:/: /'

echo "# реестр (целиком)"
grep -wo "$1" $SSLDIR/php/dump.xml | sort -u
if [ "${1:0:7}" = 'http://' ]; then
	grep -wo $with_www $SSLDIR/php/dump.xml | sort -u
	grep -wo $without_www $SSLDIR/php/dump.xml | sort -u
fi
echo "# реестр (домен)"
grep -wo "$domain" $SSLDIR/php/dump.xml | sort -u
