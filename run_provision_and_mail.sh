#!/bin/sh
set -eu

# ------------------------------------------------------------
# run_provision_and_mail.sh
# Optional: NAME/EMAIL als Positionsargumente
# Fallback: aus ENV lesen
#
# Erforderliche ENV-Variablen (nach Auflösung der Positionsargumente):
#   WG_LOGIN_USER      - UI Login Benutzer
#   WG_LOGIN_PASS      - UI Login Passwort
#   CLIENT_NAME        - Name des neuen Clients (oder 1. Positionsargument)
#   CLIENT_EMAIL       - E-Mail des neuen Clients (oder 2. Positionsargument)
#   SMTP_HOST          - Mailserver Host (default: automation.blox42.rocks)
#   SMTP_USER          - SMTP Benutzer (z.B. vpn@blox42.rocks)
#   SMTP_PASS          - SMTP Passwort
#   FROM_EMAIL         - Absender-Adresse (z.B. vpn@blox42.rocks)
#
# Optionale ENV-Variablen:
#   SMTP_PORT          - Standard 465 (SMTPS). Für STARTTLS nutze 587.
#   OUT_DIR            - Standard ./out
#   ATTACH_QR          - "true"|"false" (Standard false)
#   PROV_SCRIPT        - Pfad Provisioning-Skript (Default ./wg_user_provisioning.sh)
#   MAIL_SCRIPT        - Pfad Mail-Skript (Default ./send_config_mail.sh)
#
# Beispiele:
#   # Positionsargumente:
#   WG_LOGIN_USER=rkeller WG_LOGIN_PASS=SuperGeheim \
#     SMTP_USER=vpn@blox42.rocks SMTP_PASS='XXX' FROM_EMAIL=vpn@blox42.rocks \
#     ./run_provision_and_mail.sh duser demo.user@blox42.rocks
#
#   # Nur ENV:
#   WG_LOGIN_USER=rkeller WG_LOGIN_PASS=SuperGeheim \
#     CLIENT_NAME=duser CLIENT_EMAIL=demo.user@blox42.rocks \
#     SMTP_USER=vpn@blox42.rocks SMTP_PASS='XXX' FROM_EMAIL=vpn@blox42.rocks \
#     ./run_provision_and_mail.sh
# ------------------------------------------------------------

# Defaults
SMTP_HOST="${SMTP_HOST:-automation.blox42.rocks}"
SMTP_PORT="${SMTP_PORT:-465}"   # SMTPS per Default
OUT_DIR="${OUT_DIR:-./out}"
ATTACH_QR="${ATTACH_QR:-false}" # QR standardmäßig aus
PROV_SCRIPT="${PROV_SCRIPT:-./wg_user_provisioning.sh}"
MAIL_SCRIPT="${MAIL_SCRIPT:-./send_config_mail.sh}"

# --- optionale Positionsargumente: NAME und EMAIL ---
# nur übernehmen, wenn sie nicht wie Flags aussehen (starten mit '-')
NAME_FROM_ARG="${1:-}"
if [ -n "${NAME_FROM_ARG}" ] && [ "${NAME_FROM_ARG#-}" = "${NAME_FROM_ARG}" ]; then
  CLIENT_NAME="${CLIENT_NAME:-$NAME_FROM_ARG}"
  shift
fi

EMAIL_FROM_ARG="${1:-}"
if [ -n "${EMAIL_FROM_ARG}" ] && [ "${EMAIL_FROM_ARG#-}" = "${EMAIL_FROM_ARG}" ]; then
  CLIENT_EMAIL="${CLIENT_EMAIL:-$EMAIL_FROM_ARG}"
  shift
fi

case "$CLIENT_EMAIL" in
  *=*)
    CLIENT_EMAIL="${CLIENT_EMAIL#*=}"
    ;;
esac
case "$CLIENT_NAME" in
  *=*)
    CLIENT_NAME="${CLIENT_NAME#*=}"
    ;;
esac

# Pflicht-ENV prüfen (nachdem ggf. Positionals gesetzt wurden)
need_env() {
  eval "[ \"\${$1:-}\" != '' ]" || { echo "Fehlende Variable: $1 (als ENV oder Positionsargument übergeben)" >&2; exit 2; }
}

need_env WG_LOGIN_USER
need_env WG_LOGIN_PASS
need_env CLIENT_NAME
need_env CLIENT_EMAIL
need_env SMTP_HOST
need_env SMTP_USER
need_env SMTP_PASS
need_env FROM_EMAIL

# Skripte prüfen
[ -x "$PROV_SCRIPT" ] || { echo "Provisioning-Skript nicht ausführbar: $PROV_SCRIPT" >&2; exit 2; }
[ -x "$MAIL_SCRIPT" ] || { echo "Mail-Skript nicht ausführbar: $MAIL_SCRIPT" >&2; exit 2; }

# Ausgabe-Verzeichnis sicherstellen
mkdir -p "$OUT_DIR" 2>/dev/null || true

echo "==> [1/2] Provisioning starten: $CLIENT_NAME <$CLIENT_EMAIL>"
# Aufruf: <login_user> <login_pass> <client_name> <client_email>
"$PROV_SCRIPT" "$WG_LOGIN_USER" "$WG_LOGIN_PASS" "$CLIENT_NAME" "$CLIENT_EMAIL"

echo "==> [2/2] Versand per Mail: $CLIENT_EMAIL über $SMTP_HOST:$SMTP_PORT (FROM: $FROM_EMAIL)"
MAIL_ARGS=""
case "$ATTACH_QR" in
  true|1) MAIL_ARGS="$MAIL_ARGS --attach-qr" ;;
  *) : ;;
esac
MAIL_ARGS="$MAIL_ARGS --out-dir $OUT_DIR"

echo "DEBUG"
echo "SMTP_HOST: $SMTP_HOST"
echo "SMTP_PORT: $SMTP_PORT"
echo "SMTP_USER: $SMTP_USER"
echo "SMTP_PASS: $SMTP_PASS"
echo "FROM_EMAIL: $FROM_EMAIL"
echo "CLIENT_NAME: $CLIENT_NAME"
echo "CLIENT_EMAIL: $CLIENT_EMAIL"
echo "ATTACH_QR: $ATTACH_QR"
echo "OUT_DIR: $OUT_DIR"
echo "CONF_PATH: ${OUT_DIR}/${CLIENT_NAME}.conf"
echo "PNG_PATH: ${OUT_DIR}/${CLIENT_NAME}.png"
echo "MAIL_ARGS: $MAIL_ARGS"
echo "PROV_SCRIPT: $PROV_SCRIPT"
echo "MAIL_SCRIPT: $MAIL_SCRIPT"
echo "END DEBUG"
# shellcheck disable=SC2086
"$MAIL_SCRIPT" "$SMTP_HOST" "$SMTP_PORT" "$SMTP_USER" "$SMTP_PASS" "$FROM_EMAIL" "$CLIENT_NAME" "$CLIENT_EMAIL" $MAIL_ARGS

echo "✓ Fertig."
