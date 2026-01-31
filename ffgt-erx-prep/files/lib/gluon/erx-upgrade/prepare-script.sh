#!/bin/sh

cp -p /lib/gluon/erx-upgrade/ubnt_erx_*.sh /tmp

. /lib/functions.sh

IMAGE="$(/usr/sbin/get_image_name)"
FILE="http://firmware.4830.org/master/sysupgrade/gluon-4830-2.1.0-${IMAGE}-sysupgrade.bin"
wget -O /tmp/sysupgrade.img "${FILE}"
if [ $? -ne 0 ]; then
  echo "Download of ${FILE} failed!"
  exit 1
else
  /lib/gluon/erx-upgrade/upload_config.sh
  if [ $? -ne 0 ]; then
    echo "Config upload failed!"
    exit 1
  fi
fi

ip route show | grep ^default >/dev/null
if [ $? -ne 0 ]; then
  cat <<EOF
Es wurde keine (IPv4-) Standardroute gefunden, vermutlich ist über den WAN-Port
kein Internetzugang möglich. Daher können wir ggf. im Config-Mode nicht auf das
Internet zugreifen und somit diesen Knoten nicht automatisch migrieren. Somit
endet die Reise hier, wir verändern nichts an diesem Knoten.

EOF
else
  cat <<EOF
Es sollte alles für die Migration vorbereitet sein ...
$(ls -la /tmp/ubnt_erx_migrate.sh /tmp/ubnt_erx_stage2.sh /tmp/sysupgrade.img 2>&1 >/tmp/files.list)
$(cat /tmp/files.list)

Wenn die drei Dateien vorhanden sind, folgendes ausführen und die Sicherheitsfrage
(»Do you want to proceed with the migration?«) mit y beantworten:

cd /tmp
./ubnt_erx_migrate.sh

Nach ca. 5 Minuten sollte sich der ER-X im Configmode von Firmware 2.1.0 befinden.
Gehe daher auf https://setup.4830.org/ und lasse Dich auf den Knoten umleiten.

Viel Erfolg ;-)

EOF
fi
