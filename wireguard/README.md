# WireGuard UI Provisioning & Mail Automation

Dieses Projekt enthält drei Skripte zur automatisierten Erstellung und Verteilung von WireGuard-Client-Konfigurationen über [wireguard-ui](https://github.com/ngoduykhanh/wireguard-ui).

This project provides three scripts to automate the provisioning and distribution of WireGuard client configurations via [wireguard-ui](https://github.com/ngoduykhanh/wireguard-ui).

---

## 🇩🇪 Deutsch

### Übersicht der Skripte

1. **`wg_user_provisioning.sh`**  
   - Meldet sich bei der WireGuard-UI an  
   - Holt die nächste freie IP-Adresse  
   - Legt einen neuen Client an  
   - Lädt die `.conf`-Datei und optional einen QR-Code (`.png`) herunter  

2. **`send_config_mail.sh`**  
   - Baut eine MIME-Mail mit der `.conf` (und optional `.png`)  
   - Sendet die Mail per SMTP mit Auth + TLS/STARTTLS  

3. **`run_provision_and_mail.sh`**  
   - Liest alle notwendigen Variablen aus ENV  
   - Ruft nacheinander `wg_user_provisioning.sh` und `send_config_mail.sh` auf  

---

### Voraussetzungen

- Linux/Unix Shell (`sh`, keine Bash-Features nötig)  
- Tools:
  - [`curl`](https://curl.se/)  
  - [`jq`](https://stedolan.github.io/jq/)  
  - [`qrencode`](https://fukuchi.org/works/qrencode/) (optional, für QR)  
  - [`base64`](https://www.gnu.org/software/coreutils/base64/) oder `openssl`  

---

### Nutzung

#### 1. ENV-Datei anlegen

Beispiel `.env`:

```env
# WireGuard UI Login
WG_LOGIN_USER=rkeller
WG_LOGIN_PASS=SuperGeheim

# Client Daten
CLIENT_NAME=duser
CLIENT_EMAIL=demo.user@blox42.rocks

# Mailserver Konfiguration
SMTP_HOST=mail.blox42.rocks
SMTP_PORT=587
SMTP_USER=vpn@blox42.rocks
SMTP_PASS=SuperGeheimesSMTPPasswort
FROM_EMAIL=automation@blox42.rocks

# Optionen
OUT_DIR=./out
ATTACH_QR=true
```

#### 2. ENV laden und Skript starten

```sh
set -a
. ./.env
set +a
./run_provision_and_mail.sh
```

Ergebnis:
- `./out/<CLIENT_NAME>.conf` → WireGuard-Konfiguration  
- `./out/<CLIENT_NAME>.png` → QR-Code (falls `qrencode` installiert)  
- Mail an `<CLIENT_EMAIL>` mit `.conf` und optional `.png`  

---

### Docker-Nutzung

```yaml
services:
  wg-provision-mail:
    build: .
    working_dir: /app
    volumes:
      - ./:/app
      - ./out:/out
    env_file:
      - .env
    command: ./run_provision_and_mail.sh
```

Build & Run:

```bash
docker build -t wg-provision .
docker run --rm --env-file .env -v "$PWD/out:/out" wg-provision
```

---

## 🇬🇧 English

### Overview of Scripts

1. **`wg_user_provisioning.sh`**  
   - Logs in to WireGuard-UI  
   - Fetches the next free IP address  
   - Creates a new client  
   - Downloads the `.conf` file and optionally a QR code (`.png`)  

2. **`send_config_mail.sh`**  
   - Builds a MIME email with `.conf` (and optional `.png`)  
   - Sends the mail via SMTP with Auth + TLS/STARTTLS  

3. **`run_provision_and_mail.sh`**  
   - Reads all required variables from ENV  
   - Calls `wg_user_provisioning.sh` and `send_config_mail.sh` sequentially  

---

### Requirements

- Linux/Unix shell (`sh`, no Bash features required)  
- Tools:
  - [`curl`](https://curl.se/)  
  - [`jq`](https://stedolan.github.io/jq/)  
  - [`qrencode`](https://fukuchi.org/works/qrencode/) (optional, for QR)  
  - [`base64`](https://www.gnu.org/software/coreutils/base64/) or `openssl`  

---

### Usage

#### 1. Create `.env`

```env
WG_LOGIN_USER=rkeller
WG_LOGIN_PASS=SuperSecret

CLIENT_NAME=duser
CLIENT_EMAIL=demo.user@blox42.rocks

SMTP_HOST=mail.blox42.rocks
SMTP_PORT=587
SMTP_USER=vpn@blox42.rocks
SMTP_PASS=SuperSecretPassword
FROM_EMAIL=automation@blox42.rocks

OUT_DIR=./out
ATTACH_QR=true
```

#### 2. Load ENV and run

```sh
set -a
. ./.env
set +a
./run_provision_and_mail.sh
```

Result:
- `./out/<CLIENT_NAME>.conf` → WireGuard configuration  
- `./out/<CLIENT_NAME>.png` → QR code (if `qrencode` installed)  
- Email to `<CLIENT_EMAIL>` with `.conf` and optional `.png`  

---

### Docker Usage

```yaml
services:
  wg-provision-mail:
    build: .
    working_dir: /app
    volumes:
      - ./:/app
      - ./out:/out
    env_file:
      - .env
    command: ./run_provision_and_mail.sh
```

Build & Run:

```bash
docker build -t wg-provision .
docker run --rm --env-file .env -v "$PWD/out:/out" wg-provision
```

---

## 🔒 Sicherheit / Security

- Zugangsdaten (Login, SMTP) niemals im Klartext ins Repo commiten  
- Nutze `.env` nur lokal oder als Secret im CI/CD  
- Session-Cookies (`/tmp/wg_cookies.jar`) enthalten Tokens → nach Nutzung löschen  
- `curl -k` nur für Testzwecke bei selbstsignierten Zertifikaten  
