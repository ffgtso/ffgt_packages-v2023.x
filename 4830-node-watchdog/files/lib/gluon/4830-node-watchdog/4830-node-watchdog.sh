#!/bin/sh

SCRIPTNAME="4830-node-watchdog"
DEBUG=false
OFFLINE_FILE="/tmp/${SCRIPTNAME}.offline"
# 135 Minutes = 8100 Secondes
MAX_DELTA=8100

# don't do anything while an autoupdater process is running
pgrep autoupdater >/dev/null
if [ "$?" == "0" ]; then
	logger -s -t "$SCRIPTNAME" -p 5 "autoupdater is running, aborting."
	exit
fi

# don't run this script if another instance is still running
exec 201<$0
flock -n 201
if [ "$?" != "0" ]; then
	logger -s -t "$SCRIPTNAME" -p 5 "failed to acquire lock, another instance of this script might still be running, aborting."
	exit
fi

# check for an active gateway and get its connection quality (TQ)
GATEWAY_TQ="$(batctl gwl | grep -e "^=>" -e "^\*" | awk -F'[()]' '{print $2}'| tr -d " ")"

# initialize empty variables
[ -n "${GATEWAY_TQ}" ] || GATEWAY_TQ=0

if [ "${GATEWAY_TQ}" -eq "0" ]; then
    $($DEBUG) && logger -s -t "$SCRIPTNAME" -p 5 "gateway TQ is ${GATEWAY_TQ}, node is considered offline"
    OFFLINE_SINCE="$(cat ${OFFLINE_FILE} 2>/dev/null)"
    if [ -n "${OFFLINE_SINCE}" ]; then
        NOW="$(date +%s)"
        OFFLINE_DELTA="$(expr ${NOW} - ${OFFLINE_SINCE})"
        if [ "${OFFLINE_DELTA}" -gt "${MAX_DELTA}" ]; then
            logger -s -t "$SCRIPTNAME" -p 5 "node is considered offline for ${OFFLINE_DELTA} seconds, initiating reboot."
            sync
            sleep 2
            reboot
        else
            $($DEBUG) && logger -s -t "$SCRIPTNAME" -p 5 "node is considered offline for ${OFFLINE_DELTA} seconds, waiting until ${MAX_DELTA} ..."
        fi
    else
        date +%s >${OFFLINE_FILE}
    fi
else
    $($DEBUG) && logger -s -t "$SCRIPTNAME" -p 5 "node is considered online, gateway TQ is ${GATEWAY_TQ}."
    if [ -f ${OFFLINE_FILE} ]; then
        rm ${OFFLINE_FILE}
    fi
fi
