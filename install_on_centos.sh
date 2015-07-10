#!/bin/bash

# curl -L https://raw.githubusercontent.com/carbonsoft/carbon_scripts/master/install_on_centos.sh > install.sh
# bash install.sh Billing oleg cur

set -eux

UPDATE_PRODUCT=${1:-Billing}
UPDATE_BRANCH=${2:-pl51}
UPDATE_VERSION=${3:-cur}
HOST=update5.carbonsoft.ru
PORT=555
GRUBCONF=/boot/grub/grub.conf

yum -y install rsync || true

echo "# Скачиваем и устанавливаем контейнеры"
exclude='--exclude=lib/modules/ --exclude=lib/firmware/ --exclude=boot/'
mkdir -p /app/base/mnt/{var,log,var/cfg}
rsync -a --progress -r --port $PORT $HOST::filearchive/profiles/$UPDATE_PRODUCT /tmp/app_list
for app in $(</tmp/app_list); do
	if [ -f /app/auth/usr/lib/locale/locale-archive ] && [ "$app" != auth ]; then # speedup install, -500mb of traffic
		mkdir -p /app/$app/usr/lib/locale/ /app/$app/usr/share/locale
		cp -av /app/{auth,$app}/usr/lib/locale/locale-archive
		cp -av /app/auth/usr/share/locale/* /app/$app/usr/share/locale/
	fi
	rsync -a -v -r --port $PORT $exclude $HOST::filearchive/$UPDATE_PRODUCT/$UPDATE_VERSION/$app/ro_image_$UPDATE_BRANCH/ /app/$app/ | cut -d '/' -f 1 | uniq
done

echo "# Устанавливаем пару необходимых вещей"
rpm -i "http://mirror.yandex.ru/epel/6/i386/epel-release-6-8.noarch.rpm" || true
sed -e 's/https/http/g' -i /etc/yum.repos.d/epel.repo
sed -e 's/https/http/g' -i /etc/yum.repos.d/epel-testing.repo
sed -e 's|Defaults    requiretty|#&|g; s|# %wheel|%wheel|g' -i /etc/sudoers
yum -y install conntrack-tools mod_wsgi python-markdown dialog git python-suds lsof ntpdate vim mc strace libxslt bind-utils python-virtualenv tcpdump m4 ipset

echo "# рестартанём все контейнеры один раз чтобы обновление работало"
for app in base auth $(</tmp/app_list); do
	for action in stop destroy build start; do
		/app/$app/service $action || true
	done
done
rsync -a -v -r /app/asr_billing/{skelet/var/lib/firebird/system/,/var/lib/firebird/system}

echo "# Обновляемся, чтобы навести лоск"
( cd /boot; git init; git add .; git commit -m "initial commit" )
/app/base/usr/local/bin/update.sh $UPDATE_PRODUCT $UPDATE_BRANCH $UPDATE_VERSION --skipcheck || true
/app/base/usr/local/bin/update.sh $UPDATE_PRODUCT $UPDATE_BRANCH $UPDATE_VERSION --skipcheck || true
/app/base/usr/local/bin/update.sh $UPDATE_PRODUCT $UPDATE_BRANCH $UPDATE_VERSION --skipcheck || true
/app/base/usr/local/bin/update.sh $UPDATE_PRODUCT $UPDATE_BRANCH $UPDATE_VERSION --skipcheck #dont ask why :C

echo "# Отключаем selinux в grub + делаем бэкап конфига)" 
cat $GRUBCONF > $GRUBCONF.$(md5sum $GRUBCONF | cut -d ' ' -f1)
while IFS= read line; do
	if [[ "$line" != *kernel* ]] || [[ "$line" = *"selinux=0"* ]]; then
		echo "$line" && continue
	fi
	echo "$line selinux=0"
done < $GRUBCONF > $GRUBCONF.without_selinux
cat $GRUBCONF.without_selinux > $GRUBCONF

echo "Установка завершена, осталось только выполнить reboot"
