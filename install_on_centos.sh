#!/bin/bash

# curl -L https://raw.githubusercontent.com/carbonsoft/carbon_scripts/master/install_on_centos.sh > install.sh
# bash install.sh Billing oleg cur

set -eu
export md5=6c117a0ebff1fe744b781654b9429499
export LANG=ru_RU.UTF-8

__system_config_network() {
	echo "# Для настройки сети попробую запустить system-config-network (Нажмите Enter)"
	read ent
	system-config-network
	/etc/init.d/network restart
}

__check_inet() {
	ping -c 1 8.8.8.8 &>/dev/null && ping -c 1 google.ru &>/dev/null && return 0
	echo "# Нет доступа в интернет"
	echo "# Настройте сеть в соответствии с документацией CentOS"
	__system_config_network
	echo "# Для повторного запуска установки запустите команду $(basename $0) $@"
	exit 15
}

__check_install_host() {
	ping -c 1 $HOST &>/dev/null && return 0
	echo "# Не могу пропинговать $HOST, проверьте подключение к сети"
	__system_config_network
	echo "# Для повторного запуска установки запустите команду $(basename $0) $@"
	exit 16
}

__install_dependency() {
	echo -n "# Проверяем и устанавливаем зависимости, необходимые для установки... "
	yum -y install dialog  &>>/var/log/carbon_install.log || true
	yum -y install rsync  &>>/var/log/carbon_install.log || true
	echo "готово"
}

__install() {
	exec 3> /dev/stdout
	__hidden_install &>>/var/log/carbon_install.log

	/app/base/usr/local/bin/installation_wizard

	reboot_message="Для завершения установки требуется перезагрузить систему."
	if [ -d '/app/xge' ]; then
		reboot_message="Установлен XGE требуется перезагрузка с ядром Carbon!"
	fi

	IPMASK="$(ip a | grep -o "$(/app/base/usr/local/bin/network_parser default_route_ip)"/[0-9]*)"
	dialog --title "Установка завершена!" \
		--yesno "${reboot_message}\nПервая загрузка может может продлиться от 5 до 10 минут!\nПосле загрузки на адресе ${IPMASK%%/*}:8080 будет доступен веб-интерфейс.\nПерезагрузить автоматически?" 10 70
	[ "$?" == "0" ] && shutdown -r now
}

show_progress() {
	local progress="$1"
	local text="$2"
	echo "$progress" | dialog --title "Установка $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION" --gauge "$text" 10 70 0 >&3
}

__setup_grub() {
	GRUBCONF=/boot/grub/grub.conf
	cat $GRUBCONF > $GRUBCONF.$(md5sum $GRUBCONF | cut -d ' ' -f1)
	while IFS= read line; do
		if [[ "$line" != *kernel* ]] || [[ "$line" = *"selinux=0"* ]]; then
			echo "$line" && continue
		fi
		echo "$line selinux=0"
	done < $GRUBCONF > $GRUBCONF.without_selinux
	cat $GRUBCONF.without_selinux > $GRUBCONF
}

__hidden_install() {
	show_progress 0 "Скачиваем контейнеры"
	exclude='--exclude=lib/modules/ --exclude=lib/firmware/ --exclude=boot/'
	mkdir -p /app/base/mnt/{var,log,var/cfg}
	rsync -a --progress -r --port $PORT $HOST::filearchive/profiles/$INSTALL_PRODUCT /tmp/app_list
	container_count="$(cat /tmp/app_list | wc -l)"

	len="30"
	i=0
	for app in $(</tmp/app_list); do
		i="$((i+1))"
		if [ -f /app/auth/usr/lib/locale/locale-archive ] && [ "$app" != auth ]; then # speedup install, -500mb of traffic
			mkdir -p /app/$app/usr/lib/locale/ /app/$app/usr/share/locale
			cp -av /app/{auth,$app}/usr/lib/locale/locale-archive
			cp -av /app/auth/usr/share/locale/* /app/$app/usr/share/locale/
		fi
		_l=""
		rsync -a -v -r --port $PORT $exclude $HOST::filearchive/$INSTALL_PRODUCT/$INSTALL_VERSION/$app/ro_image_$INSTALL_BRANCH/ /app/$app/ | cut -d '/' -f 1 |\
			while read line; do
				[ "$_l" == "$line" ] && continue
				echo "$line"
				_l="$line"
				show_progress "$((len/container_count*i))" "Скачиваем данные контейнера $app, необходимые для инициализации ($i из $container_count):\n /app/$app/$line"
			done

		# TODO: Сделать закачку дельты
		#		mkdir -p /install_delta
		#		delta_target="/install_delta"
		#		CARBON_UPDATE_CACHE=/mnt/var/cache/carbon_update/
		#		rsync -a -v -r --port $PORT $exclude $HOST::filearchive/$INSTALL_PRODUCT/$INSTALL_VERSION/$app/output/$INSTALL_BRANCH/delta/ $CARBON_UPDATE_CACHE/$app/$UPDATE_BRANCH/delta
		#		cd /app/$app
		#        while read fname; do
		#                if [ -f "$fname" ]; then
		#                        rm -f "$fname" || true
		#                fi
		#        done < $CARBON_UPDATE_CACHE/$app/$UPDATE_BRANCH/${app}_delta_rm.list
		#        rsync --block-size=40507 -c -a $CARBON_UPDATE_CACHE/$app/$UPDATE_BRANCH/delta/* $APPTMP/$app || true

	done

	show_progress 35 "Устанавливаем необходимые пакеты с помощью yum"
	rpm -i "http://mirror.yandex.ru/epel/6/i386/epel-release-6-8.noarch.rpm" || true
	sed -e 's/https/http/g' -i /etc/yum.repos.d/epel.repo
	sed -e 's/https/http/g' -i /etc/yum.repos.d/epel-testing.repo
	sed -e 's|Defaults    requiretty|#&|g; s|# %wheel|%wheel|g' -i /etc/sudoers
	yum -y install conntrack-tools mod_wsgi python-markdown dialog git python-suds lsof ntpdate vim mc strace libxslt bind-utils python-virtualenv tcpdump m4 ipset system-config-network-tui

	show_progress 40 "Инициализируем контейнеры"
	len="10"
	i=-2
	for app in base auth $(</tmp/app_list); do
		i="$((i+1))"
		[ "$i" -ge "1" ] && show_progress $((40+len/container_count*i)) "Инициализируем контейнер $app ($i из $container_count)"
		for action in stop destroy build start; do
			echo "Выполняю $app $action"
			/app/$app/service $action || true
		done
	done

	if [ -d '/app/asr_billing/' ]; then
		rsync -a -v -r /app/asr_billing/{skelet/var/lib/firebird/system/,/var/lib/firebird/system}
	fi
	mkdir -p /app/base/var/reg/
	cp /tmp/app_list /app/base/var/reg/${INSTALL_PRODUCT}.profile

	[ ! -d '/boot/.git/' ] && ( cd /boot; git init; git add .; git commit -m "initial commit" )

	len="30"
	i=0
	_l=""
	echo "" > /tmp/updated_apps
	/app/base/usr/local/bin/update_download.sh $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION --skipcheck --update-server $HOST:$PORT | \
	while read line; do
		echo "$line"
		if echo "$line" | grep -q "Проверяем обновления для"; then
			app="${line##* }"
			if [ "$app" != "$_l" ] && ! grep -q "$app" /tmp/updated_apps; then
				i="$((i+1))"
				_l="$app"
				echo "$app" >> /tmp/updated_apps
			fi
			show_progress "$((50+len/container_count*i))" "Скачиваем контейнер $app ($i из $container_count)"
		fi
	done || true

	show_progress 80 "Обновляем контейнеры до последней версии"
	/app/base/usr/local/bin/update.sh $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION --skipcheck --update-server $HOST:$PORT || true
	show_progress 85 "Обновляем контейнеры до последней версии"
	/app/base/usr/local/bin/update.sh $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION --skipcheck --update-server $HOST:$PORT || true
	show_progress 90 "Обновляем контейнеры до последней версии"
	/app/base/usr/local/bin/update.sh $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION --skipcheck --update-server $HOST:$PORT || true
	show_progress 95 "Обновляем контейнеры до последней версии"
	/app/base/usr/local/bin/update.sh $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION --skipcheck --update-server $HOST:$PORT  #dont ask why :C

	show_progress 97 "Отключаем selinux в grub + делаем бэкап конфига"
	__setup_grub || true
	show_progress 100 "Запускаем специфические настройки для каждого контейнера"
	if [ -d /app/reductor ]; then
		app=reductor
		/app/$app/service setup || true
	fi
}

__get_branch_version() {
	read INSTALL_BRANCH INSTALL_VERSION <<< "$( curl "http://${HOST}:8024/get_version_to_update.php?product=$INSTALL_PRODUCT&cur_branch=$INSTALL_BRANCH" 2>/dev/null)"
}

__get_update_product() {
	curl $HOST:8024/products.list 2>/dev/null > /tmp/products
	num=1
	while read profile descr; do
		echo "$num) $descr"
		num=$((1+$num))
	done < /tmp/products

	selectnum=0
	while [ "$selectnum" -lt "1" -o "$selectnum" -ge "$num" ]; do
		echo -n "Введите номер продукта для установки: "
		read selectnum
		[[ "$selectnum" =~ ^[0-9]+$ ]] || selectnum=-100
	done
	read INSTALL_PRODUCT descr <<< "$(sed "${selectnum}q;d" /tmp/products)"
}

__ask_branch() {
	[ -n "${INSTALL_BRANCH:-}" ] && return 0
	echo "Выберете какую ветку установить:"
	echo "1) master (рекомендуется)"
	echo "2) devel"
	echo -n ">> "
	read INSTALL_BRANCH
	while [ "$INSTALL_BRANCH" != "1" -a "$INSTALL_BRANCH" != "2" ]; do
		echo $INSTALL_BRANCH
		echo "Введите номер 1 для установки master ветки или 2 для devel ветки"
		echo -n ">> "
		read INSTALL_BRANCH
	done
	INSTALL_BRANCH=${INSTALL_BRANCH//1/master}
	INSTALL_BRANCH=${INSTALL_BRANCH//2/devel}
}

usage() {
	echo "$0 [ INSTALL_PRODUCT INSTALL_BRANCH INSTALL_VERSION HOST PORT ]"
	echo "Example: $0 Billing devel cur update51.carbonsoft.ru 555"
	echo "Если не передать аргументов скипт запустится в интерактивном режиме"
	exit 0
}

main() {
	params="${@//-/}"
	[ "${params:-}" = "usage" -o "${params:-}" = "help" ] && usage

	__check_inet "$@"
	__install_dependency
	HOST=update51.carbonsoft.ru
	PORT=555

	if [ "$#" != 5 ]; then
		__get_update_product
		__ask_branch
		__get_branch_version
	else
		INSTALL_PRODUCT=${1:-Billing}
		INSTALL_BRANCH=${2:-integra}
		INSTALL_VERSION=${3:-cur}
		HOST=${4:-update51.carbonsoft.ru}
		PORT=${5:-555}
	fi

	__check_install_host "$@"
	echo "Устанавливаю $INSTALL_PRODUCT $INSTALL_BRANCH $INSTALL_VERSION с сервера $HOST:$PORT"
	__install
}

main "$@"
