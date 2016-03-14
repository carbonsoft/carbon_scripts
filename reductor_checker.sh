#!/bin/bash

# works only for reductor on centos
# for reductor on billing check $? after curl instead of stdout
# usage:
#       ./reductor_checker.sh http://bad_url1.ru http://bad_url2.ru
#       ./reductor_checker.sh < /path/to/url.list

_echo() {
        if [ "$VERBOSE" = '1' ]; then
                echo "$@"
        fi
}

check_url() {
        blocked=0
        for i in {1..100}; do
                printf "\b\b\b\b\b\b\b\b\b\b %3d / 100" $i
                if [ "$(curl -sS $url)" = '302 Found. Site Block' ]; then
                        _echo " blocked"
                        ((blocked++)) || true
                else
                        _echo " opened"
                fi
        done
        printf "\nblocked $blocked/100 times\n"
}

VERBOSE=0
if [ "$1" = '-v' ]; then
        VERBOSE=1
        shift
fi

if [ "$#" -gt '0' ]; then
        for url in $@; do
                check_url "$url"
        done
        exit 0
fi

while read -r url tmp; do
        check_url "$url"
done
