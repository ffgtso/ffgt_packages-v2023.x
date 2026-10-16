#!/bin/sh
export LC_ALL=C
q() { /sbin/uci -q "$@"; }
g() { q get "gluon-node-info.@location[0].$1"; }
s() { [ "$(g "$1")" = "$2" ] || { q set "gluon-node-info.@location[0].$1=$2" && h=1; }; }
e() { if g "$1" >/dev/null; then q delete "gluon-node-info.@location[0].$1" && h=1; fi; }
save() { [ -z "$h" ] || { q commit gluon-node-info && h=; }; }
log() { logger -t mesh-switch "$*"; }
num() { case "$1" in ''|*[!0-9]*) return 1;; esac; [ "${#1}" -le 10 ] && [ "$1" -le 2147483647 ]; }
domain() { case "$1" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac; [ -f "/lib/gluon/domains/$1.json" ]; }
branch() { case "$1" in ''|*[!a-zA-Z0-9_-]*) return 1;; esac; [ "$(q get "autoupdater.$1")" = branch ]; }
[ "$(awk '{print int($1)}' /proc/uptime)" -ge 900 ] || exit 0
mkdir /tmp/mesh-switch.lock 2>/dev/null || exit 0
trap 'rm -rf /tmp/mesh-switch.lock' 0
trap 'exit 1' HUP INT TERM
f=/tmp/mesh-switch.lock/reply
c=$(g locode)
if [ -z "$c" ]; then
 c=$(q get gluon.core.domain)
 domain "$c" || exit 1
 s locode "$c" && save || exit 1
else domain "$c" || exit 1; fi
if [ "$(g tgtloc)" = "$c" ]; then
 e tgtloc && e switchtime && save || exit 1
fi
m=$(cat /lib/gluon/core/sysconfig/primary_mac)
x=${m##*:}
case "$x" in [0-9a-fA-F][0-9a-fA-F]) sleep "$(printf %d "0x$x")";; *) exit 1;; esac
b=$(q get autoupdater.settings.branch)
p=$(awk -v a="$(g latitude)" -v o="$(g longitude)" 'BEGIN {
 r="^[+-]?[0-9]+([.][0-9]+)?$"
 if(a ~ r && o ~ r && a>=-90 && a<=90 && o>=-180 && o<=180)
  printf "lat=%.7f&lon=%.7f",a,o
}')
if [ -n "$p" ] && branch "$b"; then
 url="geoloc.php?get=newmesh&node=$m&$p&loc=$c&aub=$b"
 if wget --timeout=2 -6 -q -O "$f" "http://setup.ipv6.4830.org/$url" ||
    wget --timeout=2 -4 -q -O "$f" "http://setup.ipv4.4830.org/$url"; then
  if awk '
   /^(DST|FRM|AUB):/ {
    k=substr($1,1,3)
    if(seen[k]++ || NF>2 || $1!=k ":") bad=1
    v[k]=$2; next
   }
   END {
    if(bad || !seen["DST"] || v["DST"]=="") exit 1
    print v["DST"]; print v["FRM"]; print v["AUB"]
   }' "$f" > "$f.parsed"; then
   { read -r d; read -r u; read -r a; } < "$f.parsed"
   [ -n "$a" ] || a=$b
   if domain "$d" && branch "$a" && { [ -z "$u" ] || num "$u"; }; then
    t=$d
    if [ "$d" = "$c" ]; then t=; u=; fi
    if [ "$(g tgtloc)" != "$t" ] || [ "$(g switchtime)" != "$u" ]; then
     if [ -n "$t" ]; then s tgtloc "$t" || exit 1
     else e tgtloc || exit 1; fi
     if [ -n "$u" ]; then s switchtime "$u" || exit 1
     else e switchtime || exit 1; fi
     save || exit 1
    fi
    if [ "$a" != "$b" ]; then
     q set "autoupdater.settings.branch=$a" && q commit autoupdater || exit 1
    fi
   else log 'invalid values'; fi
  else log 'invalid reply'; fi
 else log 'query failed'; fi
fi
t=$(g tgtloc)
u=$(g switchtime)
if [ -n "$u" ] && num "$u" && domain "$t" && [ "$t" != "$c" ]; then
 if [ "$(date +%s)" -ge "$u" ]; then
  log "switching $c -> $t"
  l=$(g locode)
  s locode "$t" && save || exit 1
  sync
  gluon-switch-domain "$t" || {
   s locode "$l" || exit 1
   save || exit 1
   log 'switch failed'
   exit 1
  }
 fi
fi
