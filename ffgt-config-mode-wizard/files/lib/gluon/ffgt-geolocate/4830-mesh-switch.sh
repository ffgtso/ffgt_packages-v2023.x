#!/bin/sh
# Query a central server for the target mesh and whether moving
# to that mesh is open right now. If so, if target mesh differs
# from current one, execute a switch followed by a reboot.

locode="$(/sbin/uci get gluon-node-info.@location[0].locode 2>/dev/null)"
if [ "x${locode}" == "x" ]; then
  logger "$0: locode unset, bailing out"
fi

curlat="$(/sbin/uci get gluon-node-info.@location[0].latitude 2>/dev/null || echo 0.0)"
curlon="$(/sbin/uci get gluon-node-info.@location[0].longitude 2>/dev/null || echo 0.0)"
# If at least lat or lon are set and plausible, let's try
if [ $(printf "%.0f" "${curlat}") != 0 -o $(printf "%.0f" "${curlon}") != 0 ]; then
 IPVXPREFIX="`/lib/gluon/ffgt-geolocate/ipv5.sh`"
 if [ "Y$IPVXPREFIX" == "Y" -o "$IPVXPREFIX" == "ipv5." ]; then
  logger "$0: IPv5 not implemented."
  exit 1
 fi
 mac="$(/sbin/uci get network.bat0.macaddr)"
 touch /tmp/getmesh.out && rm /tmp/getmesh.out
 wget -q -O /tmp/getmesh.out "http://setup.${IPVXPREFIX}4830.org/geoloc.php?get=mesh&node=${mac}&lat=${curlat}&lon=${curlon}"
 if [ -e /tmp/getmesh.out ]; then
  DSTMESH="$(awk </tmp/getmesh.out '/^DST:/ {printf("%s", $2);}')"
  STRTIME="$(awk </tmp/getmesh.out '/^FRM:/ {printf("%s", $2);}')"
  if [ "X${STRTIME}" = "X" ]; then
   STRTIME="0"
  fi
  if [ "${DSTMESH}" != "${locode}" ]; then
   tgtloc="`/sbin/uci get gluon-node-info.@location[0].tgtloc 2>/dev/null`"
   if [ "${DSTMESH}" != "${tgtloc}" ]; then
    /sbin/uci set gluon-node-info.@location[0].tgtloc="${DSTMESH}"
    /sbin/uci commit gluon-node-info
    tgtloc="`/sbin/uci get gluon-node-info.@location[0].tgtloc 2>/dev/null`"
   fi
   if [ ${STRTIME} -gt 0 ]; then
    now="$(date +%s)"
    if [ ${now} -gt ${STRTIME} ]; then
     /sbin/uci set gluon-node-info.@location[0].locode="${DSTMESH}"
     /sbin/uci delete gluon-node-info.@location[0].tgtloc
     /sbin/uci commit gluon-node-info
     sleep 1
     sync
     gluon-switch-domain "${DSTMESH}"
    fi
   fi
  fi
 fi
fi
