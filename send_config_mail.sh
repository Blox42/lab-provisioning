#!/bin/sh
set -eu

# send_config_mail.sh – versendet .conf und optional .png via SMTP (TLS/STARTTLS)
# Usage:
#   ./send_config_mail.sh <SMTP_HOST> <SMTP_PORT> <SMTP_USER> <SMTP_PASS> \
#     <FROM_EMAIL> <CLIENT_NAME> <CLIENT_EMAIL> [--attach-qr] [--out-dir DIR] [--subject TEXT]

require() { command -v "$1" >/dev/null 2>&1 || { echo "Fehlt: $1" >&2; exit 2; }; }
require curl

# Portables Base64 (BusyBox/GNU/OpenSSL)
b64encode_file() {
  f="$1"
  if command -v base64 >/dev/null 2>&1; then
    # BusyBox erwartet stdin oder -i
    base64 < "$f"
  elif command -v openssl >/dev/null 2>&1; then
    # -A = single line; wir umbrechen danach
    openssl base64 -A -in "$f"
  else
    echo "Weder 'base64' noch 'openssl' vorhanden." >&2
    exit 2
  fi
}

# Fold portabel (falls 'fold' fehlt, weglassen – ist für MIME optional)
fold76() {
  if command -v fold >/dev/null 2>&1; then
    fold -w 76
  else
    cat
  fi
}

if [ $# -lt 7 ]; then
  echo "Usage: $0 <SMTP_HOST> <SMTP_PORT> <SMTP_USER> <SMTP_PASS> <FROM_EMAIL> <CLIENT_NAME> <CLIENT_EMAIL> [--attach-qr] [--out-dir DIR] [--subject TEXT]" >&2
  exit 2
fi

SMTP_HOST="$1"; shift
SMTP_PORT="$1"; shift
SMTP_USER="$1"; shift
SMTP_PASS="$1"; shift
FROM_EMAIL="$1"; shift
CLIENT_NAME="$1"; shift
CLIENT_EMAIL="$1"; shift

ATTACH_QR=false
OUT_DIR="./out"
SUBJECT="WireGuard-Konfiguration / WireGuard configuration for ${CLIENT_NAME}"

while [ $# -gt 0 ]; do
  case "$1" in
    --attach-qr) ATTACH_QR=true; shift ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --subject) SUBJECT="$2"; shift 2 ;;
    *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
  esac
done

CONF_PATH="${OUT_DIR}/${CLIENT_NAME}.conf"
PNG_PATH="${OUT_DIR}/${CLIENT_NAME}.png"

[ -s "$CONF_PATH" ] || { echo "Config-Datei nicht gefunden: $CONF_PATH" >&2; exit 1; }
if $ATTACH_QR && [ ! -s "$PNG_PATH" ]; then
  echo "Warnung: QR-PNG nicht gefunden: $PNG_PATH — sende nur .conf" >&2
  ATTACH_QR=false
fi

PROTO="smtp"
[ "$SMTP_PORT" = "465" ] && PROTO="smtps"

TMPDIR="$(mktemp -d)"; trap 'rm -rf "$TMPDIR"' EXIT
MAILFILE="${TMPDIR}/mail.mime"
BOUNDARY="bnd_$(date +%s)_$$"

# Header + Body
{
  printf "From: %s\n" "$FROM_EMAIL"
  printf "To: %s\n" "$CLIENT_EMAIL"
  printf "Subject: %s\n" "$SUBJECT"
  printf "MIME-Version: 1.0\n"
  printf "Content-Type: multipart/mixed; boundary=\"%s\"\n" "$BOUNDARY"
  printf "\n--%s\n" "$BOUNDARY"
  printf "Content-Type: text/plain; charset=UTF-8\n"
  printf "Content-Transfer-Encoding: 8bit\n\n"
  cat <<'BODY'
Hallo,

im Anhang findest du deine WireGuard-Konfiguration (.conf).
Optional liegt zusätzlich ein QR-Code (.png) bei, den du in der WireGuard-App scannen kannst.

---
Hello,

attached is your WireGuard configuration (.conf).
Optionally, a QR code (.png) is included for quick import in the WireGuard app.

Viele Grüße / Kind regards
BODY
} >"$MAILFILE"

# .conf anhängen
CONF_BASENAME="$(basename "$CONF_PATH")"
{
  printf "\n--%s\n" "$BOUNDARY"
  printf "Content-Type: application/octet-stream; name=\"%s\"\n" "$CONF_BASENAME"
  printf "Content-Transfer-Encoding: base64\n"
  printf "Content-Disposition: attachment; filename=\"%s\"\n\n" "$CONF_BASENAME"
  b64encode_file "$CONF_PATH" | fold76
} >>"$MAILFILE"

# optional QR anhängen
if $ATTACH_QR; then
  PNG_BASENAME="$(basename "$PNG_PATH")"
  {
    printf "\n--%s\n" "$BOUNDARY"
    printf "Content-Type: image/png; name=\"%s\"\n" "$PNG_BASENAME"
    printf "Content-Transfer-Encoding: base64\n"
    printf "Content-Disposition: attachment; filename=\"%s\"\n\n" "$PNG_BASENAME"
    b64encode_file "$PNG_PATH" | fold76
  } >>"$MAILFILE"
fi

# abschließen
printf "\n--%s--\n" "$BOUNDARY" >>"$MAILFILE"

# Versand
curl --url "${PROTO}://${SMTP_HOST}:${SMTP_PORT}" \
     --mail-from "$FROM_EMAIL" \
     --mail-rcpt "$CLIENT_EMAIL" \
     --upload-file "$MAILFILE" \
     --user "${SMTP_USER}:${SMTP_PASS}" \
     --ssl-reqd \
     --connect-timeout 10 \
     --max-time 60 \
     -sS

echo "E-Mail an ${CLIENT_EMAIL} versendet. Anhänge: ${CONF_BASENAME}$( $ATTACH_QR && printf ', %s' "$PNG_BASENAME" || printf '' )"