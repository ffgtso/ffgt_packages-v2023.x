#!/bin/sh

# HACK, FIXME; if /bin/wget does not exists, create a symlink from /usr/bin/wget
if [ ! -e /bin/wget ]; then test -e /usr/bin/wget && ln -s /usr/bin/wget /bin/wget ; fi

if [ ! -e /tmp/run/setup-data-sent -o $# -gt 0 ]; then
 isconfigured="`/sbin/uci get gluon-setup-mode.@setup_mode[0].configured`"
 setupifmissing="`/sbin/ifconfig br-setup >/dev/null 2>&1 ; echo $?`"
 if [ "${isconfigured}" != "1" -o "${setupifmissing}" != "1" ]; then
  # Bloody v4/v6 issues ... From an IPv4-only upstream, the preferred IPv6 AAAA record results in connection errors.
  USEIPV4=1
  USEIPV6=0
  /bin/ping -q -c 3 setup.ipv4.4830.org >/dev/null 2>&1
  if [ $? -ne 0 ]; then
   USEIPV4=0
   /bin/ping -q -c 3 setup.ipv6.4830.org >/dev/null 2>&1
   if [ $? -eq 0 ]; then
    USEIPV6=1
   fi
  fi
  if [ $USEIPV4 -eq 1 ]; then
   IPVXPREFIX="ipv4."
  else
   IPVXPREFIX="ipv6."
  fi

  mac=`/sbin/ifconfig eth0 | /usr/bin/awk '/HWaddr/ {print $NF;}'`
  localip="0.0.0.0"
  /sbin/ifconfig br-setup >/dev/null
  if [ $? -eq 0 ]; then
   localip="`/sbin/ifconfig br-setup | /usr/bin/awk '/inet addr:/ {inet=$2; gsub("addr:", "", inet); printf("%s", inet);}'`"
  else
   /sbin/ifconfig br-wan  >/dev/null
   if [ $? -eq 0 ]; then
    localip="`/sbin/ifconfig br-wan | /usr/bin/awk '/inet addr:/ {inet=$2; gsub("addr:", "", inet); printf("%s", inet);}'`"
   fi
  fi
  hostname="$(/sbin/uci get system.@system[0].hostname|sed -e 's/ /%20/g')"
  boardname="$(sed -e 's/ /%20/g' </tmp/sysinfo/board_name 2>/dev/null)"
  firmware="$(sed -e 's/ /%20/g' </lib/gluon/release 2>/dev/null)"
  /bin/wget -q -O /dev/null "http://setup.${IPVXPREFIX}4830.org/register.php?name=$hostname&mac=$mac&ip=$localip&dev=$boardname&fw=$firmware" && /bin/touch /tmp/run/setup-data-sent
 fi
fi

