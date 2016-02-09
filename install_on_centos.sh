#!/bin/bash

# curl -L https://raw.githubusercontent.com/carbonsoft/carbon_scripts/master/install_on_centos.sh > install.sh
# bash install.sh Billing oleg cur

set -eu
export md5=6c117a0ebff1fe744b781654b9429499
export LANG=ru_RU.UTF-8

__check_inet() {
	ping -c 1 8.8.8.8 && ping -c 1 google.ru && return 0
	echo "# Нет доступа в интернет"
	echo "# Настройте сеть: http://docs.carbonsoft.ru/x/NgMVAw"
	echo "# Если сеть настроена, но вы видите это сообщение - свяжитесь с тех. поддержкой CarbonSoft"
	echo "# Для повторного запуска установки запустите команду $0 $@"
	exit 15
}

__check_install_host() {
	ping -c 1 $HOST && return 0
	echo "# Не могу пропинговать $HOST, проверьте подключение к сети"
	echo "# Для повторного запуска установки запустите команду $0 $@"
	exit 16
}


__install() {
	GRUBCONF=/boot/grub/grub.conf

	yum -y install rsync || true

	echo "# Скачиваем и устанавливаем контейнеры"
	exclude='--exclude=lib/modules/ --exclude=lib/firmware/ --exclude=boot/'
	mkdir -p /app/base/mnt/{var,log,var/cfg}
	rsync -a --progress -r --port $PORT $HOST::filearchive/profiles/$INSTALL_PRODUCT /tmp/app_list
	for app in $(</tmp/app_list); do
		if [ -f /app/auth/usr/lib/locale/locale-archive ] && [ "$app" != auth ]; then # speedup install, -500mb of traffic
			mkdir -p /app/$app/usr/lib/locale/ /app/$app/usr/share/locale
			cp -av /app/{auth,$app}/usr/lib/locale/locale-archive
			cp -av /app/auth/usr/share/locale/* /app/$app/usr/share/locale/
		fi
		rsync -a -v -r --port $PORT $exclude $HOST::filearchive/$INSTALL_PRODUCT/$INSTALL_VERSION/$app/ro_image_$INSTALL_BRANCH/ /app/$app/ | cut -d '/' -f 1 | uniq
	done

	echo "# Устанавливаем пару необходимых вещей"
	rpm -i "http://mirror.yandex.ru/epel/6/i386/epel-release-6-8.noarch.rpm" || true
	sed -e 's/https/http/g' -i /etc/yum.repos.d/epel.repo
	sed -e 's/https/http/g' -i /etc/yum.repos.d/epel-testing.repo
	sed -e 's|Defaults    requiretty|#&|g; s|# %wheel|%wheel|g' -i /etc/sudoers
	yum -y install conntrack-tools mod_wsgi python-markdown dialog git python-suds lsof ntpdate vim mc strace libxslt bind-utils python-virtualenv tcpdump m4 ipset system-config-network-tui

	echo "# рестартанём все контейнеры один раз чтобы обновление работало"

	for app in base auth $(</tmp/app_list); do
		for action in stop destroy build start; do
			/app/$app/service $action || true
		done
	done
	[ -d '/app/asr_billing/' ] && rsync -a -v -r /app/asr_billing/{skelet/var/lib/firebird/system/,/var/lib/firebird/system}
	mkdir -p /app/base/var/reg/
	cp /tmp/app_list /app/base/var/reg/${INSTALL_PRODUCT}.profile

	echo "# Обновляемся, чтобы навести лоск"
	[ ! -d '/boot/.git/' ] && ( cd /boot; git init; git add .; git commit -m "initial commit" )
	/app/base/usr/local/bin/update.sh $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION --skipcheck --update-server $HOST:$PORT || true
	/app/base/usr/local/bin/update.sh $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION --skipcheck --update-server $HOST:$PORT || true
	/app/base/usr/local/bin/update.sh $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION --skipcheck --update-server $HOST:$PORT || true
	/app/base/usr/local/bin/update.sh $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION --skipcheck --update-server $HOST:$PORT  #dont ask why :C

	echo "# Отключаем selinux в grub + делаем бэкап конфига)"
	cat $GRUBCONF > $GRUBCONF.$(md5sum $GRUBCONF | cut -d ' ' -f1)
	while IFS= read line; do
		if [[ "$line" != *kernel* ]] || [[ "$line" = *"selinux=0"* ]]; then
			echo "$line" && continue
		fi
		echo "$line selinux=0"
	done < $GRUBCONF > $GRUBCONF.without_selinux
	cat $GRUBCONF.without_selinux > $GRUBCONF

	if [ -d '/app/xge' ]; then
		echo "**********************************************************************"
		echo "* ВНИМАНИЕ!!!!! Установлен XGE требуется перезагрузка с ядром Carbon *"
		echo "**********************************************************************"
	fi
	echo "Установка завершена, осталось только выполнить reboot"
}

__get_branch_version() {
	read INSTALL_BRANCH INSTALL_VERSION <<< "$( curl "http://${HOST}:8024/get_version_to_update.php?product=$INSTALL_PRODUCT&cur_branch=$INSTALL_BRANCH")"
}

__get_update_product() {
	curl $HOST:8024/products.list > /tmp/products
	num=1
	echo Выбирите продукт, который хотите установить:
	while read line; do
		echo "$num) $line"
		num=$((1+$num))
	done < /tmp/products

	selectnum=0
	while [ "$selectnum" -lt "1" -o "$selectnum" -ge "$num" ]; do
		echo -n "Введите цифру выбранного продукта(>0 и <$num): "
		read selectnum
		[[ "$selectnum" =~ ^[0-9]+$ ]] || selectnum=-100
	done
	read INSTALL_PRODUCT descr <<< "$(sed "${selectnum}q;d" /tmp/products)"
}

usage() {
	echo $0 [ INSTALL_PRODUCT INSTALL_BRANCH INSTALL_VERSION HOST PORT ]
	echo Example: $0 Billing devel cur update51.carbonsoft.ru 555
	echo Если не передать аргументов скипт запустится в интерактивном режиме
	exit 0
}

main() {
	params="${@//-/}"
	[ "${params:-}" = "usage" -o "${params:-}" = "help" ] && usage

	__check_inet "$@"

	if [ "$#" != 5 ]; then
		INSTALL_BRANCH=devel
		HOST=update51.carbonsoft.ru
		__get_update_product
		__get_branch_version
		PORT=555
		__check_install_host "$@"
	else
		INSTALL_PRODUCT=${1:-Billing}
		INSTALL_BRANCH=${2:-integra}
		INSTALL_VERSION=${3:-cur}
		HOST=${4:-update51.carbonsoft.ru}
		PORT=${5:-555}
		__check_install_host "$@"
	fi

	echo Устанавливаю $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION с сервера $HOST:$PORT
	__install
}

main "$@"
