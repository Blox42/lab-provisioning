# Minimal, klein (~10–15 MB plus Tools)
FROM alpine:3.20

# System-Tools: curl (SMTP + HTTP), jq (JSON), qrencode (QR-PNG), openssl (Base64-Fallback), ca-certs (TLS)
RUN apk add --no-cache \
      curl jq qrencode openssl ca-certificates tzdata \
    && update-ca-certificates

# App-Verzeichnis
WORKDIR /app

# Skripte kopieren
# Erwartet, dass diese Dateien im Build-Context liegen:
#  - wg_user_provisioning.sh
#  - send_config_mail.sh
#  - run_provision_and_mail.sh
COPY wg_user_provisioning.sh send_config_mail.sh run_provision_and_mail.sh /app/

# Ausführbar machen
RUN chmod +x /app/*.sh

# Non-root User
RUN addgroup -S app && adduser -S -G app app \
    && mkdir -p /out \
    && chown -R app:app /app /out
USER app

# Sinnvolle Defaults (kann per ENV/--env-file überschrieben werden)
ENV OUT_DIR=/out \
    ATTACH_QR=true

# Ausgabe-Verzeichnis als Volume
VOLUME ["/out"]

# Standard-Kommando: Orchestrator-Skript liest ENV, ruft die zwei anderen Skripte
ENTRYPOINT ["/app/run_provision_and_mail.sh"]