#!/bin/sh
#/etc/rc.common

START=50

# Run every 15 seconds ...
/lib/gluon/config-mode/notify-setup.sh force
((sleep 15 ; /lib/gluon/setup-mode/rc.d/S50ffgt-tell-setup.sh)&)
# Reboot if configured AND in setup mode for more that 3600 seconds (i. e. 1 hour) -- accidental invocation?
configured=$(/sbin/uci get gluon-setup-mode.@setup_mode[0].configured 2>/dev/null)
rc=$?
if [ ${rc} -eq 0 -a "${configured}" == "1" ]; then
 /usr/bin/awk < /proc/uptime '{if($1 > 3600.0) {printf("/sbin/reboot\n");} else {printf("echo -n\n");}}'| /bin/sh
fi

# Add prefix of WAN interface, i. e. br-setup's LAN, so we can use non-standard
# LAN setups (like e. g. 198.51.100.0/24 or public v4) as well.
WANPFX=$(ip -4 route show >/tmp/ip4route.out && awk -v dev=$(awk </tmp/ip4route.out '/^default/ {x=0; for(i=1; i<NF; i++) {if($i=="dev") {x=i+1; i=NF;}} if(x>0) {print $x;}}') '/\// {printf("%s\n", $1);}' </tmp/ip4route.out)
if [ "${WANPFX}X" != "X" ]; then
 iptables -n -L INPUT | grep "${WANPFX}" || (iptables -I INPUT -s "${WANPFX}" -p tcp --dport 80 -j ACCEPT ||: ; iptables -I INPUT -s "${WANPFX}" -p tcp --dport 22 -j ACCEPT ||:)
fi
