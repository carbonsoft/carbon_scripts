#!/bin/bash

set -eux

UPDATE_PRODUCT=${1:-Billing}
UPDATE_BRANCH=${2:-devel}
UPDATE_VERSION=${3:-cur}
HOST=update5.carbonsoft.ru
PORT=555
GRUBCONF=/boot/grub/grub.conf
DST_RO_IMAGE=$HOST::filearchive/$UPDATE_PRODUCT/$UPDATE_VERSION/base/ro_image_$UPDATE_BRANCH/
exclude='--exclude=lib/modules/ --exclude=lib/firmware/ --exclude=boot/'
exclude="$exclude $(echo $exclude | sed 's|=|&addon/|g')" # + addon/ to all

echo "# Скачиваем и устанавливаем контейнеры"
mkdir -p /app/base/mnt/{var,log,var/cfg} /var/backup/

download() {
	rsync -a --progress -r --port $PORT $@
}

download $exclude $DST_RO_IMAGE/addon/ /app/base/
download $$HOST::filearchive/profiles/$UPDATE_PRODUCT /tmp/app_list

for app in auth $(</tmp/app_list); do
	download $exclude $HOST::filearchive/$UPDATE_PRODUCT/$UPDATE_VERSION/$app/ro_image_$UPDATE_BRANCH/ /app/$app/
done

echo "# Устанавливаем пару необходимых вещей"
rpm -i "http://mirror.yandex.ru/epel/6/i386/epel-release-6-8.noarch.rpm" || true
sed -e 's/https/http/g' -i /etc/yum.repos.d/epel.repo
sed -e 's/https/http/g' -i /etc/yum.repos.d/epel-testing.repo
yum -y install conntrack-tools mod_wsgi python-markdown

echo "# Обновляемся, чтобы навести лоск"
/app/base/usr/local/bin/update.sh $UPDATE_PRODUCT $UPDATE_BRANCH $UPDATE_VERSION

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
