#!/bin/sh
# Query a central server for the target mesh and whether moving
# to that mesh is open right now. If so, if target mesh differs
# from current one, execute a switch followed by a reboot.

locode="$(/sbin/uci get gluon-node-info.@location[0].locode 2>/dev/null)"
if [ "x${locode}" == "x" ]; then
 gluondomain="$(/sbin/uci get gluon.core.domain)"
 if [ "${gluondomain}" != "" ]; then
  logger "$0: locode unset, migration foobar? Setting to ${gluondomain} ..."
  /sbin/uci set gluon-node-info.@location[0].locode="${gluondomain}" ||:
  /sbin/uci commit gluon-node-info
  locode="${gluondomain}"
 else
  logger "$0: locode unset, gluon.core.domain unset: bailing out."
  exit 0
  fi
fi

uptime=$(awk </proc/uptime '{printf("%.0f", $1);}')
if [ ${uptime} -lt 900 ]; then
  logger "$0: uptime too low, bailing out"
  exit 0
fi

# We're now supposed to run ...
LASTOCTET=$(cut -d : -f6 /lib/gluon/core/sysconfig/primary_mac)
DELAYSECS=$(printf %d 0x${LASTOCTET})
# ... but delay hammering the server pseudo-randomly
sleep ${DELAYSECS}

branch=$(uci get autoupdater.settings.branch)
AUBRNCH="${branch}"

# Empty string == unset in UCI
switchtime="$(/sbin/uci get gluon-node-info.@location[0].switchtime 2>/dev/null)"
# Ensure these values are numbers
curlat="$(/sbin/uci get gluon-node-info.@location[0].latitude 2>/dev/null || echo 0.0)"
curlon="$(/sbin/uci get gluon-node-info.@location[0].longitude 2>/dev/null || echo 0.0)"
# Sanitize
#curlat="$(echo "${curlat}" | sed -e 's/ //g')"
#curlon="$(echo "${curlon}" | sed -e 's/ //g')"
curlat="$(printf "%.7f" "${curlat}")"
curlon="$(printf "%.7f" "${curlon}")"
# If at least lat or lon are set and plausible, let's try
if [ $(printf "%.0f" "${curlat}") != 0 -o $(printf "%.0f" "${curlon}") != 0 ]; then
 mac="$(cat /lib/gluon/core/sysconfig/primary_mac)"
 # Clear previous data
 touch /tmp/getmesh.out && rm /tmp/getmesh.out
 # Query for where we should be according to our coordinates and if a
 # starttime is set to actually switch to that mesh
 querystring="$(echo "geoloc.php?get=newmesh&node=${mac}&lat=${curlat}&lon=${curlon}&loc=${locode}&aub=${branch}" | sed -e 's/ //g')"
 wget --timeout=2 -6 -q -O /tmp/getmesh.out "http://setup.ipv6.4830.org/${querystring}"
 if [ $? -ne 0 ]; then
   wget --timeout=2 -4 -q -O /tmp/getmesh.out "http://setup.ipv4.4830.org/${querystring}"
 fi
 if [ -e /tmp/getmesh.out ]; then
  DSTMESH="$(awk </tmp/getmesh.out '/^DST:/ {printf("%s", $2);}')"
  STRTIME="$(awk </tmp/getmesh.out '/^FRM:/ {printf("%s", $2);}')"
  AUBRNCH="$(awk </tmp/getmesh.out '/^AUB:/ {printf("%s", $2);}')"
  if [ "X${AUBRNCH}" = "X" ]; then
   AUBRNCH="${branch}"
  fi

  # If no STaRTTIME returned, delete a stored switchtime in UCI; otherwise,
  # if stored switchtime differs from STaRTTIME, set this as new switchtime.
  if [ "X${STRTIME}" = "X" ]; then
   if [ "X${switchtime}" != "X" ]; then
     /sbin/uci delete gluon-node-info.@location[0].switchtime ||:
     /sbin/uci commit gluon-node-info
   fi
  else
   if [ "${switchtime}" != "${STRTIME}" ]; then
    /sbin/uci set gluon-node-info.@location[0].switchtime="${STRTIME}"
    /sbin/uci commit gluon-node-info
   fi
  fi

  # If DeSTinationMESH differs from current one, save as t(ar)g(e)tloc(ode)
  # in UCI if it differs from previously stored one (reduce uci commits as
  # much as possible)
  if [ "${DSTMESH}" != "${locode}" ]; then
   tgtloc="$(/sbin/uci get gluon-node-info.@location[0].tgtloc 2>/dev/null)"
   if [ "${DSTMESH}" != "${tgtloc}" ]; then
    /sbin/uci set gluon-node-info.@location[0].tgtloc="${DSTMESH}"
    /sbin/uci commit gluon-node-info
   fi
  fi
 else
  logger "$0: call for get=newmesh failed on setup.4830.org ..."
 fi
fi

# Change Autoupdater branch if setup server says so
if [ "${AUBRNCH}" != "${branch}" ]; then
  uci set autoupdater.settings.branch="${AUBRNCH}"
  uci commit autoupdater
fi

# Now, check if there's a switchtime set and a target locode as well
# and if it's time to switch
now="$(date +%s)"
switchtime="$(/sbin/uci get gluon-node-info.@location[0].switchtime 2>/dev/null)"
tgtloc="$(/sbin/uci get gluon-node-info.@location[0].tgtloc 2>/dev/null)"

if [ "${switchtime}" != "" ]; then
 if [ "${tgtloc}" != "" ]; then
  if [ ${now} -gt ${switchtime} ]; then
   logger "$0: switchtime reached, switching to mesh ${tgtloc} in a second."
   sleep 1
   # Set 4830.org's locode, as gluon-switch-domain only sets gluon.core.domain,
   # then delete tgtloc and switchtime from UCI, as we will execute the switch
   # now.
   /sbin/uci set gluon-node-info.@location[0].locode="${tgtloc}"
   /sbin/uci delete gluon-node-info.@location[0].tgtloc ||:
   /sbin/uci delete gluon-node-info.@location[0].switchtime ||:
   /sbin/uci commit gluon-node-info
   sync
   sleep 2
   gluon-switch-domain "${tgtloc}"
   # System should now reboot ...
  else
   logger "$0: switchtime to switch to mesh ${tgtloc} not reached, exiting."
  fi
 else
  logger "$0: switchtime set but no target mesh defined, that should not happen; exiting ..."
 fi
else
 if [ "${tgtloc}" != "" -a "${tgtloc}" != "${locode}" ]; then
  logger "$0: switch from ${locode} to ${tgtloc} neccessary, but no switchtime set."
 else
  logger "$0: no switchtime set, nothing to do."
 fi
fi
