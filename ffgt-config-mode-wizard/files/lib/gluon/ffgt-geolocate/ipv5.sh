#!/bin/sh
#
# nslookup myip.opendns.com 208.67.222.222 | awk '/^Address/ {ip=$NF;} END{printf("%s\n", ip);}'
#
# Bloody v4/v6 issues ... From an IPv4-only upstream, the preferred IPv6 AAAA record results in connection errors.
# Now serves as is-online test as well, setting /tmp/is_online appropriately if online with IPv4 and/or IPv6.

# 2020-08-30: Use gluon-wan to force v4 resolving via WAN if present.
if [ -e /tmp/is_online ]; then /bin/rm /tmp/is_online ; fi
USEIPV4=1
USEIPV6=0
gluon-wan /bin/ping -q -c 3 setup.ipv4.4830.org >/dev/null 2>&1
if [ $? -ne 0 ]; then
 USEIPV4=0
 /bin/ping -q -c 3 setup.ipv6.4830.org >/dev/null 2>&1
 if [ $? -eq 0 ]; then
  USEIPV6=1
 fi
fi
IPVXPREFIX="ipv6."
if [ $USEIPV4 -eq 1 ]; then
 IPVXPREFIX="ipv4."
fi
if [ $USEIPV4 -eq 0 -a $USEIPV6 -eq 0 ]; then
 echo "$0: IPv5 not implemented." >/dev/stderr
 IPVXPREFIX="ipv5."
 else
 echo "online with ${IPVXPREFIX}" >/tmp/is_online
fi

echo $IPVXPREFIX
exit 0
