# Proxmox IAM — Add User via API

This folder contains `add_user.sh`, a script that manages Proxmox users and groups using the Proxmox REST API (no `pveum`). It:
- Derives and sanitizes a `userid` from an email and realm
- Ensures a target group exists (idempotent)
- Creates or updates the user (OpenID users have no password)
- Ensures the user is a member of the target group

## Requirements
- `curl`, `jq`
- A Proxmox account or API token with permissions to manage users/groups (e.g., role with `User.*` and `Group.*` on `/access`).

## Usage
```
./add_user.sh -e user@example.com [-r Blox42] [-g Admin] [-u customuserid]
```

## Environment Variables (CLI flags override env)
- Email: `EMAIL`, `MAILADDRESS`, `SURVEY_EMAIL`, `SURVEY_MAILADDRESS`, `ADDUSER_EMAIL`, `ADD_USER_EMAIL`, `USER_EMAIL`
- Group: `GROUP`, `GROUPNAME`, `SURVEY_GROUP`, `SURVEY_GROUPNAME`, `ADDUSER_GROUP`, `ADD_USER_GROUP`, `USER_GROUP`
- Realm: `REALM`, `SURVEY_REALM`, `ADDUSER_REALM`, `ADD_USER_REALM`, `USER_REALM` (default: `Blox42`)
- Username override: `USER_NAME_OVERRIDE`, `USER_NAME`, `USERNAME`, `USERID`, `SURVEY_*` variants

## Proxmox API Authentication
Provide one of the following:
- API Token (recommended):
  - `PVE_USER` (e.g., `root@pam`), `PVE_TOKEN_NAME`, `PVE_TOKEN_VALUE`
- Username/Password (falls back to ticket auth):
  - `PVE_USER`, `PVE_PASSWORD`

## API Endpoint
- `PROXMOX_API_URL` (default: `https://127.0.0.1:8006/api2/json`)
- Or set `PROXMOX_HOST` (host[:port]) to auto-derive the URL
- `PROXMOX_INSECURE=1` to skip TLS verify for self-signed certs (default is `1`)

## Examples
- Token-based auth:
```
PVE_USER=root@pam \
PVE_TOKEN_NAME=ci \
PVE_TOKEN_VALUE=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
PROXMOX_HOST=proxmox.example.com \
./add_user.sh -e alice@example.com -r Blox42 -g Admin
```

- Password-based auth:
```
PVE_USER=root@pam \
PVE_PASSWORD='your-secret' \
PROXMOX_API_URL=https://proxmox.example.com:8006/api2/json \
./add_user.sh -e bob@example.com -g Admin
```

## Behavior Notes
- User IDs are `<name>@<realm>`; name only allows `[A-Za-z0-9_.-]`. The script sanitizes the source (email or override) accordingly.
- The OpenID realm must already exist in Proxmox. The script warns if it cannot find the realm via `/access/domains`.
- Group creation and membership changes are idempotent; re-running the script is safe.

## Troubleshooting
- 401/403: verify credentials, token privileges, and that the API URL is correct.
- TLS errors: use `PROXMOX_INSECURE=1` for self-signed certificates (or install the CA).
- Permission denied on group/user endpoints: ensure your role includes `User.*` and `Group.*` on `/access`.
