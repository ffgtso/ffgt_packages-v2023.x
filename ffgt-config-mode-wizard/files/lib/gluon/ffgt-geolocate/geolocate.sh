#!/bin/sh
# This script is supposed to be run (once) from lua
IW="/usr/sbin/iw"
if [ ! -e $IW ]; then
 echo >/tmp/fake_iw -e "#!/bin/sh\ncat /dev/null"
 chmod +x /tmp/fake_iw
 IW="/tmp/fake_iw"
fi
export IW

WLANDEV="$(${IW} dev | /usr/bin/awk 'BEGIN{idx=1;} /Interface client/ {iface[idx]=$2; ifacemap[$2]=idx; idx++}; END{for(i=1; i<idx; i++) {printf("%s ", iface[i]);}}')"
if [ "X${WLANDEV}" = "X" ]; then
 echo "$0: no WiFi device detected"
 logger "$0: no WiFi device detected"
 exit 0
fi

runnow=0
force=0
isconfigured="`/sbin/uci get gluon-setup-mode.@setup_mode[0].configured 2>/dev/null`"
if [ "$isconfigured" != "1" ]; then
 isconfigured=0
fi

if [ ! -e /tmp/run/geolocate-data-sent ]; then
 runnow=1
fi

if [ $# -eq 1 ]; then
  if [ "$1" = "force" ]; then
    runnow=1
    force=1
    if [ ! -e /tmp/run/geolocate-data-sent ]; then
      rm /tmp/run/geolocate-data-sent
    fi
  fi
fi

if [ ${runnow} -eq 1 ]; then
 IPVXPREFIX="`/lib/gluon/ffgt-geolocate/ipv5.sh`"
 if [ "Y$IPVXPREFIX" == "Y" -o "$IPVXPREFIX" == "ipv5." ]; then
  logger "$0: IPv5 not implemented."
  exit 1
 fi

 mac=`/sbin/uci get network.bat0.macaddr`
 # FIXME. On multiband devices, check wlan1 as well!
 for dev in ${WLANDEV}
 do
  ${IW} dev ${dev} scan >/dev/null 2>&1
  if [ $? -ne 0 ]; then
   /sbin/ifconfig ${dev} up
   sleep 2
   ${IW} dev ${dev} scan >/dev/null 2>&1
  fi
 done
 wget -q -O /dev/null "$( (for dev in ${WLANDEV}; do ${IW} ${dev} scan; done) | /usr/bin/awk -v mac=$mac -v ipv4prefix=$IPVXPREFIX -f /lib/gluon/ffgt-geolocate/preparse.awk)" && /bin/touch /tmp/run/geolocate-data-sent
 # On success only ...
 if [ -e /tmp/run/geolocate-data-sent ]; then
  if [ ${force} -eq 1 ]; then
    curlat=""
  else
    curlat="$(/sbin/uci get gluon-node-info.@location[0].longitude 2>/dev/null)"
  fi
  if [ "X${curlat}" = "X" ]; then
   sleep 5
   wget -q -O /tmp/geoloc.out "http://setup.${IPVXPREFIX}4830.org/geoloc.php?list=me&node=$mac"
   if [ -e /tmp/geoloc.out ]; then
    # Actually, we might want to sanity check the reply, as it could be empty or worse ... (FIXME) 
    /bin/cat /dev/null >/tmp/geoloc.sh
    haslocation="`/sbin/uci get gluon-node-info.@location[0] 2>/dev/null]`"
    if [ "${haslocation}" != "location" ]; then
     echo "/sbin/uci add gluon-node-info location" >>/tmp/geoloc.sh
    fi
    # Honour existing share_location setting; if missing, create & set to '1'
    hasshare="`/sbin/uci get gluon-node-info.@location[0].share_location 1>/dev/null 2>&1; echo $?`"
    if [ "${hasshare}" != "0" ]; then
     echo "/sbin/uci set gluon-node-info.@location[0].share_location=1" >>/tmp/geoloc.sh
    fi
    /usr/bin/awk </tmp/geoloc.out '/^LAT:/ {printf("/sbin/uci set gluon-node-info.@location[0].latitude=%s\n", $2);} /^LON:/ {printf("/sbin/uci set gluon-node-info.@location[0].longitude=%s\n", $2);} /^ADR:/ {printf("/sbin/uci set gluon-node-info.@location[0].addr=%c%s%c\n", 39, $2, 39);} /^CTY:/ {printf("/sbin/uci set gluon-node-info.@location[0].city=%s\n", $2);} /^ZIP:/ {printf("/sbin/uci set gluon-node-info.@location[0].zip=%s\n", $2);} /^LOC:/ {printf("/sbin/uci set gluon-node-info.@location[0].locode=%s\n", $2);} END{printf("/sbin/uci commit gluon-node-info\n");}' >>/tmp/geoloc.sh
    /bin/sh /tmp/geoloc.sh
    if [ $isconfigured -ne 1 ]; then
     loc="`/sbin/uci get gluon-node-info.@location[0].locode 2>/dev/null`"
     adr="`/sbin/uci get gluon-node-info.@location[0].addr 2>/dev/null`"
     if [ "x${loc}" != "x" -a "x${adr}" != "x" ]; then
      hostname="${loc}-${adr}"
      /sbin/uci set system.@system[0].hostname="${hostname}"
      /sbin/uci commit system
     fi
    fi
   fi
  fi
 fi
fi
