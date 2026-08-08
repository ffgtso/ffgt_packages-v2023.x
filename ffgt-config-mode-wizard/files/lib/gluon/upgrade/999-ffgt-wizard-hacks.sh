#!/bin/sh
# Cleanup

START=1

BOARD="$(cat /tmp/sysinfo/board_name)"

logger "$0: started for ${BOARD}"

if [ "${BOARD}" = "dlink,dap-x1860-a1" ]; then
  RSSID_DEV="$(uci get system.rssid_wlan1.dev 2>&1)"
  if [ "${RSSID_DEV}" = "wlan1" ]; then
    uci set system.rssid_wlan1.dev='mesh1' ||:
    uci commit system >/dev/null 2>&1 ||:
  fi
fi

logger "$0: done"
