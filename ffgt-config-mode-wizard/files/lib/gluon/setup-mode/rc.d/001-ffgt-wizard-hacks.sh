#!/bin/sh
# Another big fat ugly hack ...
# But as we don't want to completely rework the Wizardry, we neet to patch our
# Firmware once after upgrade.

START=1

logger "$0: started"

# HACK, FIXME; if /bin/wget does not exists, create a symlink from /usr/bin/wget
if [ ! -e /bin/wget ]; then test -e /usr/bin/wget && ln -s /usr/bin/wget /bin/wget ; fi

if [ -e /lib/gluon/config-mode/model/gluon-config-mode/wizard-ffgt.lua ]; then
  mv /lib//gluon/config-mode/model/gluon-config-mode/wizard-ffgt.lua /lib/gluon/config-mode/model/gluon-config-mode/wizard.lua ||:
fi

if [ -e /lib/gluon/config-mode/wizard-ffgt ]; then
  mv /lib/gluon/config-mode/wizard /lib/gluon/config-mode/wizard-dist ||:
  mv /lib/gluon/config-mode/wizard-ffgt /lib/gluon/config-mode/wizard ||:
  for i in 0050-autoupdater-info.lua 0250-outdoor.lua 0300-mesh-vpn.lua
  do
    if [ -e /rom/lib/gluon/config-mode/wizard/$i ]; then
      cp -p /rom/lib/gluon/config-mode/wizard/$i /lib/gluon/config-mode/wizard/ ||:
    fi
  done
  for i in 0100-hostname.lua 0400-geo-location.lua 0500-contact-info.lua
  do
    if [ -e /lib/gluon/config-mode/wizard/$i ]; then
      /bin/rm /lib/gluon/config-mode/wizard/$i ||:
    fi
  done
fi

if [ -e /lib/gluon/config-mode/reboot-ffgt ]; then
  mv /lib/gluon/config-mode/reboot /lib/gluon/config-mode/reboot-dist ||:
  mv /lib/gluon/config-mode/reboot-ffgt /lib/gluon/config-mode/reboot ||:
fi

BOARD="$(cat /tmp/sysinfo/board_name)"
if [ "${BOARD}" = "dlink,dap-x1860-a1" ]; then
  RSSID_DEV="$(uci get system.rssid_wlan1.dev 2>&1)"
  if [ "${RSSID_DEV}" = "wlan1" ]; then
    uci set system.rssid_wlan1.dev='mesh1' ||:
    uci commit system >/dev/null 2>&1 ||:
  fi
fi

COMMIT_WIRELESS=0
EOS_CHECK=$(uci get wireless.dep_radio0.ssid >/dev/null 2>&1; echo $?)
if [ ${EOS_CHECK} -eq 0 ]; then
  uci delete wireless.dep_radio0 ||:
  COMMIT_WIRELESS=1
fi

LEGACY_CHECK=$(uci get wireless.legacy_radio0.ssid >/dev/null 2>&1 ; echo $?)
if [ ${LEGACY_CHECK} -eq 0 ]; then
  uci delete wireless.legacy_radio0 ||:
  COMMIT_WIRELESS=1
fi

LEGACY_CHECK=$(uci get wireless.legacy_radio1.ssid >/dev/null 2>&1 ; echo $?)
if [ ${LEGACY_CHECK} -eq 0 ]; then
  uci delete wireless.legacy_radio1 ||:
  COMMIT_WIRELESS=1
fi

DEFAULT_CHECK=$(uci get wireless.default_radio0.ssid >/dev/null 2>&1 ; echo $?)
if [ ${DEFAULT_CHECK} -eq 0 ]; then
  uci delete wireless.default_radio0 ||:
  COMMIT_WIRELESS=1
fi

DEFAULT_CHECK=$(uci get wireless.default_radio1.ssid >/dev/null 2>&1 ; echo $?)
if [ ${DEFAULT_CHECK} -eq 0 ]; then
  uci delete wireless.default_radio1 ||:
  COMMIT_WIRELESS=1
fi

DEFAULT_CHECK=$(uci get wireless.default_radio2.ssid >/dev/null 2>&1 ; echo $?)
if [ ${DEFAULT_CHECK} -eq 0 ]; then
  uci delete wireless.default_radio2 ||:
  COMMIT_WIRELESS=1
fi

if [ ${COMMIT_WIRELESS} -eq 1 ]; then
  uci commit wireless >/dev/null 2>&1 ||:
fi

logger "$0: done"
