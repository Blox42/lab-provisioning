#!/bin/sh
set -eu

# ======= FESTE VORGABEN =======
WG_URL="https://coordinator.blox42.rocks"   # bei Bedarf anpassen; Schema wird unten abgesichert
COOKIE_JAR="/tmp/wg_cookies.jar"
OUT_DIR="./out"
SUGGEST_SR="__default_any__"
APPLY_CONFIG=true
DOWNLOAD_PATH="/download?clientid="   # ggf. anpassen
ALLOWED_JSON='["172.30.0.0/24","10.10.0.0/16","10.11.0.0/16","10.12.0.0/16","192.168.100.0/24","172.16.0.0/16"]'
USE_SERVER_DNS=false
ENABLED=true
TELEGRAM_USERID=""
ENDPOINT=""
PUBLIC_KEY=""
PRESHARED_KEY=""
CONNECT_TIMEOUT=10
MAX_TIME=60
# ===============================

if [ $# -ne 4 ]; then
  echo "Usage: $0 <wg-login-user> <wg-login-pass> <client-name> <client-email>" >&2
  exit 2
fi

WG_LOGIN_USER="$1"
WG_LOGIN_PASS="$2"
NAME="$3"
EMAIL="$4"

# Falls WG_URL ohne Schema gesetzt ist (z. B. "host.tld"), auf https:// normalisieren
case "$WG_URL" in
  http://*|https://*) : ;;
  *) WG_URL="https://$WG_URL" ;;
esac

need() { command -v "$1" >/dev/null 2>&1 || { echo "Fehlt: $1" >&2; exit 2; }; }
need curl; need jq
QR_OK=false; command -v qrencode >/dev/null 2>&1 && QR_OK=true

mkdir -p "$OUT_DIR"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT

echo "==> Login"
LOGIN_PAYLOAD=$(jq -n --arg u "$WG_LOGIN_USER" --arg p "$WG_LOGIN_PASS" '{username:$u,password:$p,rememberMe:false}')
CODE=$(curl -sS -w "%{http_code}" -o "$TMP" -c "$COOKIE_JAR" \
  -H 'Accept: application/json, text/javascript, */*; q=0.01' \
  -H 'Content-Type: application/json' \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H "Origin: ${WG_URL}" \
  -H "Referer: ${WG_URL}/" \
  -A 'curl/7.x' \
  --compressed \
  --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
  -X POST "${WG_URL}/login" --data-raw "$LOGIN_PAYLOAD")
[ "$CODE" = "200" ] || [ "$CODE" = "204" ] || { echo "Login fehlgeschlagen ($CODE)"; cat "$TMP"; exit 1; }

echo "==> Nächste freie IPs holen"
MS="$(date +%s%3N 2>/dev/null || date +%s)"
CODE=$(curl -sS -w "%{http_code}" -o "$TMP" -b "$COOKIE_JAR" \
  -H 'Accept: application/json, text/javascript, */*; q=0.01' \
  -H 'Content-Type: application/json' \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H "Origin: ${WG_URL}" \
  -H "Referer: ${WG_URL}/" \
  -A 'curl/7.x' \
  --compressed \
  --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
  -X GET "${WG_URL}/api/suggest-client-ips?sr=${SUGGEST_SR}&_=${MS}")
[ "$CODE" = "200" ] || { echo "suggest-client-ips fehlgeschlagen ($CODE)"; cat "$TMP"; exit 1; }
ALLOCATED_JSON=$(jq -c '.' "$TMP")
echo "   -> $(echo "$ALLOCATED_JSON" | jq -r '.[]' | paste -sd' ' -)"

echo "==> Client anlegen: $NAME <$EMAIL>"
NEW_CLIENT_JSON=$(jq -n \
  --arg name "$NAME" --arg email "$EMAIL" --arg tel "$TELEGRAM_USERID" \
  --arg endpoint "$ENDPOINT" \
  --argjson use_dns "$USE_SERVER_DNS" \
  --argjson enabled "$ENABLED" \
  --arg pub "$PUBLIC_KEY" --arg psk "$PRESHARED_KEY" \
  --argjson allocated "$ALLOCATED_JSON" \
  --argjson allowed "$ALLOWED_JSON" \
  --argjson extra '[]' '
  {name:$name,email:$email,telegram_userid:$tel,
   allocated_ips:$allocated,allowed_ips:$allowed,extra_allowed_ips:$extra,
   endpoint:$endpoint,use_server_dns:$use_dns,enabled:$enabled,
   public_key:$pub,preshared_key:$psk}')

CODE=$(curl -sS -w "%{http_code}" -o "$TMP" -b "$COOKIE_JAR" -c "$COOKIE_JAR" \
  -H 'Accept: application/json, text/javascript, */*; q=0.01' \
  -H 'Content-Type: application/json' \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H "Origin: ${WG_URL}" \
  -H "Referer: ${WG_URL}/" \
  -A 'curl/7.x' \
  --compressed \
  --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
  -X POST "${WG_URL}/new-client" --data-raw "$NEW_CLIENT_JSON")
[ "$CODE" = "200" ] || [ "$CODE" = "201" ] || { echo "Client-Anlage fehlgeschlagen ($CODE)"; cat "$TMP"; exit 1; }

# Direkter Versuch, die ID aus der Antwort zu lesen
CLIENT_ID=$(jq -r '(.Client.ID // .Client.Id // .Client.id // .client.ID // .client.Id // .client.id // .ID // .Id // .id // .data.ID // .data.Id // .data.id // empty)' "$TMP" | head -n1 || true)

if [ -z "${CLIENT_ID:-}" ]; then
  echo "==> Fallback: Client-ID via /api/clients suchen"
  CODE=$(curl -sS -w "%{http_code}" -o "$TMP" -b "$COOKIE_JAR" \
    -H 'Accept: application/json, text/javascript, */*; q=0.01' \
    -H 'Content-Type: application/json' \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H "Origin: ${WG_URL}" \
    -H "Referer: ${WG_URL}/" \
    -A 'curl/7.x' \
    --compressed \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    -X GET "${WG_URL}/api/clients")
  [ "$CODE" = "200" ] || { echo "/api/clients fehlgeschlagen ($CODE)"; cat "$TMP"; exit 1; }
  CLIENT_ID=$(jq -r --arg n "$NAME" '
    .[]? as $it
    | ($it.Client? // $it.client? // $it) as $c
    | select(($c.Name // $c.name // "") == $n)
    | ($c.ID // $c.Id // $c.id)
  ' "$TMP" | head -n1)
fi
[ -n "$CLIENT_ID" ] || { echo "Client-ID nicht gefunden"; exit 1; }
echo "   -> $CLIENT_ID"

if [ "$APPLY_CONFIG" = "true" ]; then
  echo "==> Apply Config"
  CODE=$(curl -sS -w "%{http_code}" -o "$TMP" -b "$COOKIE_JAR" \
    -H 'Accept: application/json, text/javascript, */*; q=0.01' \
    -H 'Content-Type: application/json' \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H "Origin: ${WG_URL}" \
    -H "Referer: ${WG_URL}/" \
    -A 'curl/7.x' \
    --compressed \
    --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
    -X POST "${WG_URL}/api/apply-wg-config" --data-raw '')
  [ "$CODE" = "200" ] || [ "$CODE" = "204" ] || { echo "Apply fehlgeschlagen ($CODE)"; cat "$TMP"; exit 1; }
fi

CONF="${OUT_DIR}/${NAME}.conf"
PNG="${OUT_DIR}/${NAME}.png"

echo "==> Config herunterladen"
curl -fsS -b "$COOKIE_JAR" \
  -H 'Accept: application/json, text/javascript, */*; q=0.01' \
  -H 'Content-Type: application/json' \
  -H 'X-Requested-With: XMLHttpRequest' \
  -H "Origin: ${WG_URL}" \
  -H "Referer: ${WG_URL}/" \
  -A 'curl/7.x' \
  --compressed \
  --connect-timeout "$CONNECT_TIMEOUT" --max-time "$MAX_TIME" \
  -X GET "${WG_URL}${DOWNLOAD_PATH}${CLIENT_ID}" -o "$CONF"
[ -s "$CONF" ] || { echo "Config-Download fehlgeschlagen"; exit 1; }
echo "   -> $CONF"

if [ "$QR_OK" = true ]; then
  echo "==> QR erzeugen"
  qrencode -o "$PNG" -r "$CONF" || true
  [ -f "$PNG" ] && echo "   -> $PNG"
fi

echo "Fertig."
