# WireGuard UI User Provisioning

Dieses Skript (`wg_user_provisioning.sh`) automatisiert die Anlage von neuen WireGuard-Clients über die [wireguard-ui](https://github.com/ngoduykhanh/wireguard-ui) API.

This script (`wg_user_provisioning.sh`) automates the provisioning of new WireGuard clients via the [wireguard-ui](https://github.com/ngoduykhanh/wireguard-ui) API.

---

## 🇩🇪 Deutsch

### Funktionen
- Login bei der WireGuard-UI API  
- Abruf der **nächsten freien IP-Adressen** via `/api/suggest-client-ips`  
- Anlage eines neuen Clients mit:
  - Name
  - E-Mail
  - festen Allowed-IPs (im Skript hinterlegt)  
- Optionales `apply-wg-config`  
- Download der **WireGuard-Konfigurationsdatei (.conf)**  
- Erzeugung eines **QR-Codes (.png)** (falls `qrencode` installiert ist)  

### Voraussetzungen
- Shell (`sh`, keine Bash-Features erforderlich)  
- Tools:
  - [`curl`](https://curl.se/)  
  - [`jq`](https://stedolan.github.io/jq/)  
  - [`qrencode`](https://fukuchi.org/works/qrencode/) (optional für QR-Code PNG)  

### Nutzung
```bash
./wg_user_provisioning.sh <wg-login-user> <wg-login-pass> <client-name> <client-email>
