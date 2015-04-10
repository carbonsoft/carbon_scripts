#!/bin/bash

# works only for reductor on centos
# for reductor on billing check $? after curl

check_url() {
	blocked=0
	for i in {1..100}; do
		if [ "$(curl -sS $url &>/dev/null)" = '302 Found. Site Block' ]; then
			((blocked++)) || true
		fi
		printf "\b\b\b\b\b\b\b\b\b\b %3d / 100" $i
	done
	printf "\n$blocked\n"
}


if [ "$#" -gt '0' ]; then
	for url in $@; do		check_url "$url"
	done

else
	while read -r url tmp; do
		check_url "$url"
	done
fi
