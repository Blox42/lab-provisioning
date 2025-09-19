#!/bin/sh
set -eu

# ------------------------------------------------------------
# run_provision_and_mail.sh
# Liest Variablen aus der Umgebung und ruft erst das
# Provisioning-Skript, dann das Mail-Skript auf.
#
# Erforderliche ENV-Variablen:
#   WG_LOGIN_USER      - UI Login Benutzer
#   WG_LOGIN_PASS      - UI Login Passwort
#   CLIENT_NAME        - Name des neuen Clients
#   CLIENT_EMAIL       - E-Mail des neuen Clients
#   SMTP_HOST          - Mailserver Host (z.B. mail.blox42.rocks)
#   SMTP_USER          - SMTP Benutzer (z.B. vpn@blox42.rocks)
#   SMTP_PASS          - SMTP Passwort
#   FROM_EMAIL         - Absender-Adresse (z.B. vpn@blox42.rocks)
#
# Optionale ENV-Variablen:
#   SMTP_PORT          - Standard 587 (STARTTLS). Für SMTPS nutze 465.
#   OUT_DIR            - Standard ./out
#   ATTACH_QR          - "true"|"false" (Standard true)
#   PROV_SCRIPT        - Pfad zum Provisioning-Skript (Default ./wg_user_provisioning.sh)
#   MAIL_SCRIPT        - Pfad zum Mail-Skript (Default ./send_config_mail.sh)
#
# Beispiel:
#   WG_LOGIN_USER=rkeller WG_LOGIN_PASS=SuperGeheim \
#   CLIENT_NAME=duser CLIENT_EMAIL=demo.user@blox42.rocks \
#   SMTP_HOST=mail.blox42.rocks SMTP_USER=vpn@blox42.rocks SMTP_PASS='XXX' FROM_EMAIL=vpn@blox42.rocks \
#   ./run_provision_and_mail.sh
# ------------------------------------------------------------

# Defaults
SMTP_PORT="${SMTP_PORT:-587}"
OUT_DIR="${OUT_DIR:-./out}"
ATTACH_QR="${ATTACH_QR:-true}"
PROV_SCRIPT="${PROV_SCRIPT:-./wg_user_provisioning.sh}"
MAIL_SCRIPT="${MAIL_SCRIPT:-./send_config_mail.sh}"

# Pflicht-ENV prüfen
need_env() { eval "[ \"\${$1:-}\" != '' ]" || { echo "Fehlende ENV-Variable: $1" >&2; exit 2; }; }

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

echo "==> [1/2] Provisioning starten: $CLIENT_NAME <$CLIENT_EMAIL>"
"$PROV_SCRIPT" "$WG_LOGIN_USER" "$WG_LOGIN_PASS" "$CLIENT_NAME" "$CLIENT_EMAIL"

echo "==> [2/2] Versand per Mail: $CLIENT_EMAIL über $SMTP_HOST:$SMTP_PORT (FROM: $FROM_EMAIL)"
MAIL_ARGS=""
if [ "${ATTACH_QR}" = "true" ] || [ "${ATTACH_QR}" = "1" ]; then
  MAIL_ARGS="$MAIL_ARGS --attach-qr"
fi
MAIL_ARGS="$MAIL_ARGS --out-dir $OUT_DIR"

# shellcheck disable=SC2086
"$MAIL_SCRIPT" "$SMTP_HOST" "$SMTP_PORT" "$SMTP_USER" "$SMTP_PASS" \
  "$FROM_EMAIL" "$CLIENT_NAME" "$CLIENT_EMAIL" $MAIL_ARGS

echo "✓ Fertig."
