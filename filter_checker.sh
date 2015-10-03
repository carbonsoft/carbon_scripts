#!/bin/bash

THREADS=15
MAINDIR=/opt/reductor_filter_monitoring
DATADIR=$MAINDIR/var/
REDIRECT_PAGE_TEMPLATE='<title>Доступ ограничен</title>'
trap show_report EXIT
trap show_report HUP


check_url() {
	local file=/tmp/random/$((RANDOM))
	if ! curl -sSL "$1" > $file; then
		echo "$1" >> $DATADIR/2
		rm -f $file
		return
	fi
	grep -q "$REDIRECT_PAGE_TEMPLATE" $file
	echo "$1" >> $DATADIR/$?
	rm -f $file
}

clean() {
	mkdir -p $DATADIR/
	for f in 0 1 2; do
		> $DATADIR/$f
	done
}

main_loop() {
	while sleep 0.1; do
		for i in $(seq 1 $THREADS); do
			read -t 1 url || break 2
			check_url $url &
		done
		wait
		show_report
	done
}

show_report() {
	echo $(date) $(wc -l < $DATADIR/0) ok / $(wc -l < $DATADIR/1) fail / $(wc -l < $DATADIR/2) not open
}

clean
main_loop
