#!/bin/sh

if [ $# -eq 2 ]; then
 lat="$1"
 lon="$2"
else
 lat=$(uci get gluon-node-info.@location[0].latitude 2>/dev/null || echo "0.00")
 lon=$(uci get gluon-node-info.@location[0].longitude 2>/dev/null || echo "0.00")
fi
targetlocode="zzz"

if [ "$lat" != "0.00" -a "$lon" != "0.00" ]; then
 # Soest
 if [ "$(echo "$lat;$lon" | awk 'BEGIN{FS=";";} {if (($1 > 51.52412 && $1 < 51.62953) && ($2 > 7.97157 && $2 < 8.18361)) {printf("true");}}')" = "true" ]; then
  targetlocode="mns"
 fi
 # Möhnesee
 if [ "$(echo "$lat;$lon" | awk 'BEGIN{FS=";";} {if (($1 > 51.41955 && $1 < 51.53651) && ($2 > 8.00611 && $2 < 8.23786)) {printf("true");}}')" = "true" ]; then
  targetlocode="mns"
 fi
 # Wickede
 if [ "$(echo "$lat;$lon" | awk 'BEGIN{FS=";";} {if (($1 > 51.48801 && $1 < 51.51323) && ($2 > 7.84540 && $2 < 7.88788)) {printf("true");}}')" = "true" ]; then
  targetlocode="mns"
 fi
 # Werl
 if [ "$(echo "$lat;$lon" | awk 'BEGIN{FS=";";} {if (($1 > 51.50447 && $1 < 51.60075) && ($2 > 7.81832 && $2 < 8.00440)) {printf("true");}}')" = "true" ]; then
  targetlocode="mns"
 fi
 # Hamm
 if [ "$(echo "$lat;$lon" | awk 'BEGIN{FS=";";} {if (($1 > 51.57963 && $1 < 51.75849) && ($2 > 7.65266 && $2 < 8.01109)) {printf("true");}}')" = "true" ]; then
  targetlocode="mns"
 fi
 # Reg.bez. Arnsberg
 if [ "$(echo "$lat;$lon" | awk 'BEGIN{FS=";";} {if (($1 > 50.72081 && $1 < 51.74574) && ($2 > 7.06009 && $2 < 8.97995)) {printf("true");}}')" = "true" ]; then
  targetlocode="mns"
 fi
fi
echo -n ${targetlocode}
