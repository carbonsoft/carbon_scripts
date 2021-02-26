#!/bin/bash

# curl -L https://raw.githubusercontent.com/carbonsoft/carbon_scripts/master/install_on_centos.sh > install.sh
# bash install.sh Billing oleg cur

set -eu
export md5=6c117a0ebff1fe744b781654b9429499
export LANG=ru_RU.UTF-8

declare HAVE_INET
declare PORT
declare HOST
declare INSTALL_PRODUCT
declare INSTALL_BRANCH
declare INSTALL_VERSION

yesno() {
	local answer
	local question="$1"
	# \e[1m - оформление жирный/яркий, \e[0m - сброс. Помогаем пользователю понять какие буквы можно вводить
	echo -ne "$question Выберите (\e[1my\e[0mes/\e[1mn\e[0mo): "
	while true; do
		read answer;
		if [[ "${answer,,}" =~ "y" ]]; then
			return 0
		elif [[ "${answer,,}" =~ "n" ]]; then
			return 1
		else
			echo
			echo -ne "Выберите (\e[1my\e[0mes/\e[1mn\e[0mo): "
		fi
	done
}

__configure_network() {
	system-config-network || true
	/etc/init.d/network restart || true
	return 0
}

__check_network() {
	if (ip -4 -o addr | grep inet | grep -qvE ':\s+lo\s+'); then
		__check_inet
		return 0
	fi
	echo -ne "# Внимание: \e[1mсеть не настроена!\e[0m "
	if [ -d '/carbon_install' ]; then
		if yesno "Запустить мастер настройки?"; then
			__configure_network
			__check_network
			return 0
		fi
	fi
	echo "# Для работы системы необходимо настроить подключение к сети"
	echo "# Настройте сеть в соответствии с документацией CentOS"
	echo "# Для повторного запуска установки запустите команду $(basename $0) $@"
	exit 15
}

__check_inet() {
	echo "# Проверяем доступ в интернет..."
	HAVE_INET=0
	ping -c 1 8.8.8.8 &>/dev/null && ping -c 1 google.ru &>/dev/null && HAVE_INET=1
	if [ "$HAVE_INET" -eq 1 ]; then
		if [ "$(__check_dhcp)" == 'TRUE' ]; then
			echo "# Есть доступ в интернет, но настройки получены от DHCP."
			echo "# Рекомендуется настроить статический IP."
			if [ -f "/carbon_install/carbon_app/reductor.tar.gz" ]; then
				if yesno "# Настроить сейчас?"; then
					__configure_network
					__check_network
				fi
			fi
		fi
		return 0
	fi
	echo "# Не обнаружен доступ в интернет"
	if yesno "# Настроить доступ в Интернет, чтобы скачать последние hotfix?"; then
		__configure_network
		__check_network
		return 0
	else
	    echo -e "# для настройки сети в будущем, воспользуйтесь командой \e[1msystem-config-network\e[0m"
		return 0
	fi
}

__check_dhcp() {
	local device_regex="(eth|em|en|p[0-9]*p)[0-9\.]+"
	local iface iface_cfg
	iface=$(ip route)
	iface=$(grep -F "default" <<< "$iface" | grep -Eo "$device_regex")
	iface_cfg="/etc/sysconfig/network-scripts/ifcfg-$iface"
	if [ ! -f "$iface_cfg" ]; then
		echo FALSE
	elif grep -Eqm1 'BOOTPROTO="?dhcp"?' "$iface_cfg"; then
		echo TRUE
	else
		echo FALSE
	fi
	return 0
}

__check_install_host() {
	[ -d '/carbon_install' ] && return 0 || true
	ping -c 1 $HOST &>/dev/null && return 0
	echo "# Не могу получить отклик от $HOST"
	echo "# Возможно, сервер установки CarbonSoft временно недоступен. Обратитесь в техническую поддержку!"
	echo "# Для повторного запуска установки запустите команду $(basename $0) $@"
	exit 16
}

yum_install() {
	local prog="$1"
	local cmd="${2:-}"
	[ -z "$cmd" ] && cmd="install"
	if [ -d '/carbon_install' ]; then
		yum -y -c /carbon_install/centos_iso_addons/yum.conf $cmd $prog &>>/var/log/carbon_install.log
		return 0
	fi
	yum -y $cmd $prog &>>/var/log/carbon_install.log
}

__install_dependency() {
	echo "# Проверяем и устанавливаем зависимости, необходимые для установки... "
	yum_install "dialog"
	yum_install "rsync"
}

__install() {
	exec 3>/dev/stdout
	
	touch /var/log/carbon_install.log
	while true; do
		if [ ! -f /tmp/log_output.lock ]; then
			a="$(tail -1 /var/log/carbon_install.log | sed -r 's/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[mGK]//g' | sed 's/[\x01-\x1F\x7F]//g')"
			echo "$a" | grep -q 'CRITICAL' && continue
			printf "\r%-80s\r" "${a:0:80}"
		fi
		sleep 0.1
		[ ! -d /proc/$$/ ] && exit 0;
	done &
	progres_pid=$!

	res=0
	__hidden_install &>>/var/log/carbon_install.log || res="$?"
	if [ "$res" == "254" ]; then
		kill -9 $progres_pid
		clear
		dialog --title "Проблема установки ${INSTALL_PRODUCT}!" --msgbox "Аппа ${app}, необходимого для установки $INSTALL_PRODUCT нет на установочном носителе.
Для продолжения настройте доступ в Интернет" 10 70
		rm -rf /app/*
		exec /usr/local/bin/carbon_install
# TODO:	elif [ "$res" != "0" ]; then
#		dialog --title "Проблема установки ${INSTALL_PRODUCT}!" --msgbox "Конец лога установки:\n$(tail -4 /var/log/carbon_install.log)" 10 70
#		exit 1
	fi

	kill -SIGPIPE $progres_pid
	sleep 0.1
	[[ -d "/proc/$progres_pid" ]] && kill -9 $progres_pid

	if [ -f /proc/$$/fd/3 ]; then
		exec 3>-
	fi

	update_issue_and_motd

	/app/base/usr/local/bin/installation_wizard

	# workaround для бага с непоказом страницы в самый <первый раз
	curl -D- http://169.254.80.81:8081/auth/getcompanyname/ &>/dev/null || true


	reboot_message="Для завершения установки требуется перезагрузить систему."
	if [ -d '/app/xge' ]; then
		reboot_message="Установлен XGE требуется перезагрузка с ядром Carbon!"
	fi

	for app in 'reductor' 'bgp_blackhole' 'netmon'; do
		if [ -d "/app/$app" ]; then
			/app/$app/service setup || true
		fi
	done
	IPMASK="$(ip a | grep -o "$(/app/base/usr/local/bin/network_parser default_route_ip)"/[0-9]*)"
	dialog --title "Поздравляем, установка завершена!" \
		--yesno "Спасибо за выбор продуктов компании Carbon Soft!\n${reboot_message}\nПервая загрузка может продлиться от 5 до 10 минут!\nПосле загрузки на адресе ${IPMASK%%/*}:8080 будет доступен веб-интерфейс.\nПерезагрузить автоматически?" 10 70
	if [ "$?" == "0" ]; then
		/etc/init.d/apps stop || true
		/etc/init.d/apps destroy || true
		shutdown -r now
	fi
}

update_issue_and_motd() {
	sed -i-s 's|^Рекомендуется продолжить установку по ssh.*$||g' /etc/issue
	echo "
Carbon Platform установлен в каталог /app
${descr%% -*} установлен в каталог /app

Для входа в меню с настройками, наберите команду menu
Для запуска диагностики, наберите команду /etc/init.d/apps check
" > /etc/motd
	echo "echo \"Для входа в панель управления откройте браузером адрес http://\$(/app/base/usr/local/bin/network_parser default_route_ip):8080/\"" >> /root/.bash_profile
}

show_progress() {
	touch /tmp/log_output.lock
	local progress="$1"
	local text="$2"
	echo "$progress" | dialog --title "Установка $INSTALL_PRODUCT $INSTALL_BRANCH" --gauge "$text" 10 70 0 >&3
	echo "$text"
	rm -f /tmp/log_output.lock
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
	service crond stop  # angel может помешать инициализации аппов
	show_progress 0 "Скачиваем контейнеры"
	exclude='--exclude=lib/modules/ --exclude=lib/firmware/ --exclude=boot/'
	mkdir -p /app/base/mnt/{var,log,var/cfg}
	app=''
	if [ -f "/carbon_install/carbon_app/${INSTALL_PRODUCT}.version" ]; then
		INSTALL_VERSION=$(<"/carbon_install/carbon_app/${INSTALL_PRODUCT}.version")
		if ! cp -a "/carbon_install/carbon_profiles/$INSTALL_PRODUCT" /tmp/app_list; then
			return 254
		fi
	elif [ "$HAVE_INET" == "0" ]; then
		return 254
	else
		if ! rsync -a --progress -r --port $PORT "$HOST::filearchive/profiles/${INSTALL_PRODUCT}" /tmp/app_list; then
			return 254
		fi
		local version_file="${INSTALL_VERSION}/version.${INSTALL_BRANCH}"
		[ "$INSTALL_VERSION" == "official" ] && version_file="version_${INSTALL_BRANCH}.official"
		if ! rsync -a --progress -r --port $PORT "$HOST::filearchive/${INSTALL_PRODUCT}/${version_file}" "/tmp/version"; then
			return 254
		fi
		read -r INSTALL_VERSION < /tmp/version
		[[ -z "$INSTALL_VERSION" ]] && return 254
	fi
	container_count="$(cat /tmp/app_list | wc -l)"

	len="30"
	i=0

	for app in $(</tmp/app_list); do
		i="$((i+1))"

		if [ -f "/carbon_install/carbon_app/${app}.tar.gz" ]; then
			show_progress "$((len/container_count*i))" "Распаковываем данные контейнера $app, необходимые для инициализации ($i из $container_count)"

			local dst_dir="/app/$app/"
			local archive_file="/carbon_install/carbon_app/${app}.tar.gz"
			local inc_file="/carbon_install/carbon_app/${app}_delta.inc"
			local delta_file="/carbon_install/carbon_app/${app}_delta.tar.gz"
			local rm_list_file="/carbon_install/carbon_app/${app}_delta_rm.list"

			mkdir -p $dst_dir
			tar -v -xzf $archive_file -C $dst_dir

			if [ -f "$delta_file" ]; then
				tar --listed-incremental=${inc_file} -v -xzf "$delta_file" -C $dst_dir
			fi

			if [ -f "$rm_list_file" ]; then
				while read fname; do
					if [ -f "${dst_dir}/$fname" ]; then
						rm -f "${dst_dir}/${fname}" || true
					fi
				done < $rm_list_file
			fi

			cache_dest_dir="/mnt/var/cache/carbon_update/${app}/${INSTALL_BRANCH}/"
			[ ! -d "$cache_dest_dir" ] && mkdir -p "$cache_dest_dir" || true
			cp -a /carbon_install/carbon_app/${app}*{inc,list,md5} "$cache_dest_dir"
		else
			if [ "$HAVE_INET" == "0" ]; then
				return 254
			fi

			if [ -f /app/auth/usr/lib/locale/locale-archive ] && [ "$app" != auth ]; then # speedup install, -500mb of traffic
				mkdir -p /app/$app/usr/lib/locale/ /app/$app/usr/share/locale
				cp -av /app/{auth,$app}/usr/lib/locale/locale-archive
				cp -av /app/auth/usr/share/locale/* /app/$app/usr/share/locale/
			fi
			_l=""
			show_progress "$((len/container_count*i))" "Скачиваем данные контейнера $app, необходимые для инициализации ($i из $container_count)"
			if ! rsync -a -v -r --port $PORT $exclude "$HOST::filearchive/${INSTALL_PRODUCT}/${INSTALL_VERSION}/$app/ro_image_${INSTALL_BRANCH}/" "/app/$app/"; then
				return 254
			fi

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
		fi
	done

	show_progress 35 "Устанавливаем необходимые пакеты с помощью yum"
	yum_install "epel-release"
	sed -e 's/https/http/g' -i /etc/yum.repos.d/epel.repo
	sed -e 's/https/http/g' -i /etc/yum.repos.d/epel-testing.repo
	sed -e 's|Defaults    requiretty|#&|g; s|# %wheel|%wheel|g' -i /etc/sudoers
	for repo in conntrack-tools mod_wsgi python-markdown dialog git python-suds lsof ntpdate vim mc strace libxslt bind-utils python-virtualenv tcpdump m4 ipset system-config-network-tui; do
		yum_install "$repo"
	done

	if ! rpm -q postfix; then
		yum_install postfix
		yum_install sendmail erase || true
	fi

	mv /etc/sysconfig/iptables /etc/sysconfig/iptables.del

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
		# принудительно синхронизируем пароли к API биллинга в других контейнерах
		/app/base/usr/local/monitoring/check_api_psw.py
	fi

	mkdir -p /app/base/var/reg/
	cp /tmp/app_list /app/base/var/reg/${INSTALL_PRODUCT}.profile

	[ ! -d '/boot/.git/' ] && ( cd /boot; git init; git add .; git commit -m "initial commit" )
	len="30"
	i=0
	_l=""

	if [ -f /carbon_install/centos_iso_addons/yum.conf ]; then
		mkdir -p /carbon_install/bin
		cat <<EOF > /carbon_install/bin/yum
#!/bin/bash
set -x
/usr/bin/yum -y -c /carbon_install/centos_iso_addons/yum.conf \$@
EOF
		chmod +x /carbon_install/bin/yum
	fi
	(
		[ -d /carbon_install/bin ] && export PATH="/carbon_install/bin:$PATH"
		i=0
		len=10
		for app in base auth $(</tmp/app_list); do
			i="$((i+1))"
			show_progress $((50+len/container_count*i)) "Запускаем update_hook $app ($i из $container_count)"
			if [ -f "/app/$app/usr/local/bin/update_hook.sh" ]; then
				if [ "$app" == "base" ]; then
					# у base хук должен отработать 100% даже если нет сетки
					/app/$app/usr/local/bin/update_hook.sh
				else
					/app/$app/service stop || true
					chroot /app/$app /usr/local/bin/update_hook.sh || true
					/app/$app/service start || true
				fi
			fi
		done
	)

	show_progress 70 "Отключаем selinux в grub + делаем резервную копию конфигурации"
	__setup_grub || true

	echo "$INSTALL_VERSION" > /app/${INSTALL_PRODUCT}.version
	echo "$INSTALL_BRANCH"  > /app/${INSTALL_PRODUCT}.branch

	# Принудительно вызовем __update_kernel для обновления ядра при установки XGE.
	if [ -d /app/xge ]; then
		if ! /app/base/usr/local/bin/update/__update_kernel; then
			/app/base/usr/local/bin/alarm 'Ошибка обновления ядра!'
		fi
	fi

	if [ "$HAVE_INET" == "1" ]; then
		if [ "$HOST" != "update51.carbonsoft.ru" ]; then
			echo "auto_update['custom_update_host']='${HOST}'" >> /app/base/cfg/config
			echo "auto_update['branch']='${INSTALL_BRANCH}'" >> /app/base/cfg/config
		fi
		read t FRESH_VERSION <<< "$( curl "http://${HOST}:8024/get_version_to_update.php?product=${INSTALL_PRODUCT}&cur_branch=${INSTALL_BRANCH}" 2>/dev/null)" || true
		[ -z "$FRESH_VERSION" -o "$FRESH_VERSION" == "error" ] && FRESH_VERSION=0
		if [ "$FRESH_VERSION" -gt "$INSTALL_VERSION" ]; then
			show_progress 90 "Обновляем контейнеры до последней версии"
			md5=6c117a0ebff1fe744b781654b9429499 /app/base/usr/local/bin/carbon_update update --skipcheck 2>&1
		fi
	fi

	show_progress 100 "Запускаем специфические настройки для каждого контейнера"
	echo "Установка завершена!"
}

__select_product() {
	clear
	echo -e " Для установки доступны следующие продукты:\n"
        echo "Billing Carbon Billing - Биллинговая система Carbon Soft
 XGE Carbon XGE Router - Маршрутизатор Carbon Soft
 Billing_Softrouter Carbon Billing-Softrouter - Биллинговая система с интегрированным маршрутизатором
 Billing_Slave Carbon Billing-Slave - Дочерний биллинг сервер
 CRB-Reductor Carbon Reductor DPI X - Фильтр трафика по спискам Роскомнадзора и Минюста
 CRB-Netmon Carbon Netmon - Мониторинг сети
 CRB-Satellite Carbon Satellite - Система тестирования фильтрации трафика" > /tmp/products
	num=1
	while read profile descr; do
		echo -e " \e[1m$num\e[0m) $descr"
		num=$((1+$num))
	done < /tmp/products
	echo ""

	selectnum=0
	while [ "$selectnum" -lt "1" -o "$selectnum" -ge "$num" ]; do
		echo -ne "Введите \e[1mномер\e[0m продукта который вы хотите установить [1]: "
		read selectnum
		# если ничего не ввели - ставим биллинг
		[[ -z "$selectnum" ]] && selectnum=1
		[[ "$selectnum" =~ ^[0-9]+$ ]] || selectnum=-100
	done
	read INSTALL_PRODUCT descr <<< "$(sed "${selectnum}q;d" /tmp/products)"
}

usage() {
	echo "$0 [ INSTALL_PRODUCT INSTALL_BRANCH INSTALL_VERSION HOST PORT ]"
	echo "Example: $0 Billing devel cur update51.carbonsoft.ru 555"
	echo "Если не передать аргументов, скрипт запустится в интерактивном режиме"
	exit 0
}

main() {
	echo "Подготовка к установке..."
	params="${@//-/}"
	[ "${params:-}" = "usage" -o "${params:-}" = "help" ] && usage

	# исправляем ссылку на репозитарий
	[[ ! -s /etc/yum/vars/releasever ]] \
		&& echo "$(sed 's/.* release \(6.[0-9]\+\) .*/\1/;t;d' /etc/centos-release)" \
		> /etc/yum/vars/releasever
	sed -i 's/^mirrorlist/#mirrorlist/;s/^#baseurl/baseurl/;s/mirror.centos.org\/centos/vault.centos.org/' \
		/etc/yum.repos.d/CentOS-Base.repo

	yum_install "system-config-network-tui" || true
	__check_network "$@"
	if ! env | grep -qm1 SSH_CLIENT; then
		if ! yesno "# Система готова к установке. Продолжить? (для установки через ssh введите no)\n"; then
			echo -e "Для повторного запуска установки введите команду \e[1mcarbon_install\e[0m"
			exit 1
		fi
	fi
	__install_dependency

	INSTALL_PRODUCT=${1:-}
	INSTALL_BRANCH=${2:-devel}
	INSTALL_VERSION=${3:-official}
	HOST=${4:-update51.carbonsoft.ru}
	PORT=${5:-555}
	[ -z "$INSTALL_PRODUCT" ] && __select_product

	__check_install_host "$@"
	echo "Устанавливаю $INSTALL_PRODUCT $INSTALL_BRANCH с сервера $HOST:$PORT"
	__install
}

main "$@"
