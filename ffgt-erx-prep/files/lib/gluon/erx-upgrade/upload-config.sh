#!/bin/sh

ID="$((/lib/gluon/label_mac.sh 2>/dev/null || echo "000000000000") | sed -e s/://g)"
FILE="/tmp/${ID}.tgz"
sysupgrade --create-backup ${FILE}
URL="https://erx.4830.org/index.php/upload"

BOUNDARY="------------------------$(date +%s%N)"
TMPREQ="$(mktemp)"

{
  printf -- "--%s\r\n" "$BOUNDARY"
  printf 'Content-Disposition: form-data; name="id"\r\n\r\n'
  printf '%s\r\n' "$ID"

  printf -- "--%s\r\n" "$BOUNDARY"
  printf 'Content-Disposition: form-data; name="file"; filename="%s"\r\n' "$(basename "$FILE")"
  printf "Content-Type: application/octet-stream\r\n\r\n"
  cat "$FILE"
  printf "\r\n--%s--\r\n" "$BOUNDARY"
} > "$TMPREQ"

wget -qO- \
  --method=POST \
  --header="Content-Type: multipart/form-data; boundary=$BOUNDARY" \
  --body-file="$TMPREQ" \
  "$URL"
RC=$?

rm -f "$TMPREQ"

exit $RC
