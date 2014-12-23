#!/bin/bash

# run: curl -L https://raw.githubusercontent.com/carbonsoft/carbon_scripts/master/install_on_centos.sh | bash

set -eux

UPDATE_PRODUCT=${1:-Billing}
UPDATE_BRANCH=${2:-devel}
UPDATE_VERSION=${3:-cur}
HOST=update5.carbonsoft.ru
PORT=555
GRUBCONF=/boot/grub/grub.conf

echo "# Скачиваем и устанавливаем контейнеры"

exclude='--exclude=lib/modules/ --exclude=lib/firmware/ --exclude=boot/'
exclude="$exclude $(echo $exclude | sed 's|=|&addon/|g')" # + addon/ to all
mkdir -p /app/base/mnt/{var,log,var/cfg} /var/backup/
rsync -a --progress -r --port $PORT $HOST::filearchive/profiles/$UPDATE_PRODUCT /tmp/app_list
for app in $(</tmp/app_list); do
	[ "$app" = 'base' ] && addon='/addon/' || addon=''
	if [ -f /app/auth/usr/lib/locale/locale-archive ] && [ "$app" != auth ]; then # speedup install, -500mb of traffic
		mkdir -p /app/$app/usr/lib/locale/ /app/$app/usr/share/locale
		cp -av /app/{auth,$app}/usr/lib/locale/locale-archive
		cp -av /app/auth/usr/share/locale/* /app/$app/usr/share/locale/
	fi
	rsync -a -v -r --port $PORT $exclude $HOST::filearchive/$UPDATE_PRODUCT/$UPDATE_VERSION/$app/ro_image_$UPDATE_BRANCH/$addon /app/$app/ | cut -d '/' -f 1,2 | uniq
done

echo "# Устанавливаем пару необходимых вещей"
rpm -i "http://mirror.yandex.ru/epel/6/i386/epel-release-6-8.noarch.rpm" || true
sed -e 's/https/http/g' -i /etc/yum.repos.d/epel.repo
sed -e 's/https/http/g' -i /etc/yum.repos.d/epel-testing.repo
sed -e 's|Defaults    requiretty|#&|g; s|# %wheel|%wheel|g' -i /etc/sudoers
yum -y install conntrack-tools mod_wsgi python-markdown dialog git
for app in base auth $(</tmp/app_list); do
	/app/$app/service stop || true
	/app/$app/service destroy || true
	/app/$app/service build || true
	/app/$app/service start || true
done

# костыль, надо разобраться с var и skelet
rsync -a -v -r /app/asr_billing/{skelet/var/lib/firebird/system/,/var/lib/firebird/system}

echo "# Обновляемся, чтобы навести лоск"
( cd /boot; git init; git add .; git commit -m "initial commit" )
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
