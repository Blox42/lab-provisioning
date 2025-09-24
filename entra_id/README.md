# add_user.sh — Ensure a user exists and is a member of “all-admins” via Microsoft Graph

This script ensures that:
- A user (identified by email/UPN) exists in your Microsoft Entra ID (Azure AD) tenant. If not found, it sends an external invitation.
- The user is a member of the group named “all-admins”. If not, it adds them.

It uses only curl and jq to call Microsoft Graph v1.0 REST APIs (no Azure CLI required).

---

## Quick Usage

- With a pre-acquired token:
```
GRAPH_TOKEN="<access-token>" ./add_user.sh -u user@domain.com -n "User Name"
```

- With client credentials (app-only):
```
TENANT_ID="<tenant-id>" \
CLIENT_ID="<app-client-id>" \
CLIENT_SECRET="<client-secret>" \
./add_user.sh -u user@domain.com
```

The script can also auto-load variables from a local `.env`.

---

## Prerequisites

- Bash (set -euo pipefail compatible)
- curl
- jq
- Microsoft Entra ID tenant with external collaboration enabled (for invitations)
- Microsoft Graph access token with suitable permissions (see below)

---

## Permissions

Application (app-only) permissions recommended:
- User.Invite.All
- User.Read.All
- Group.ReadWrite.All

If you only need to read groups, Group.Read.All is sufficient (but adding members requires Group.ReadWrite.All).

Admin consent is required for these permissions.

---

## Authentication options

You can authenticate in one of two ways:

1) Pre-acquired token
- Set GRAPH_TOKEN with a valid Microsoft Graph access token.
- Example (Azure CLI delegated token):
    - az login --tenant "<your-tenant-id>"
    - export GRAPH_TOKEN="$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv)"

2) Client credentials (app-only)
- Register an app in Entra ID (single tenant is fine).
- Grant Microsoft Graph API application permissions: User.Invite.All, User.Read.All, Group.ReadWrite.All.
- Grant admin consent.
- Create a client secret.
- Set these environment variables:
    - TENANT_ID
    - CLIENT_ID
    - CLIENT_SECRET
- The script will request a token at runtime and auto-refresh on 401 once when possible.

Optional: Manually request a token (for verification)
- POST to https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token
- grant_type=client_credentials
- scope=https://graph.microsoft.com/.default

---

## Configuration via .env

The script will automatically load variables from a .env file in the current directory:
- Lines must be KEY=VALUE without surrounding quotes or spaces.
- Comment lines starting with # are ignored.
- Typical keys: TENANT_ID, CLIENT_ID, CLIENT_SECRET, GRAPH_TOKEN.

Note: Values containing spaces may not parse correctly because the loader uses xargs.

---

## Usage

#!/bin/bash
#
# add_user.sh - ensure a user exists (create or invite) and ensure membership in group "all-admins"
#
# Uses Microsoft Graph REST via curl + jq only (no az CLI).
#
# How to create the required Microsoft Graph access token
#
# This script needs a Graph token that can:
# - Invite external users (POST /invitations)
# - Read users (GET /users)
# - Add users to groups (POST /groups/{id}/members/$ref)
#
# Required permissions (Application permissions for app-only):
# - User.Invite.All
# - User.Read.All
# - Group.ReadWrite.All
#
# Recommended (app-only, client credentials):
# 1) Register an app in Entra ID (Azure AD):
#    - Entra ID > App registrations > New registration (single tenant is fine)
#    - Note the "Application (client) ID" and "Directory (tenant) ID"
# 2) Grant Microsoft Graph API permissions:
#    - API permissions > Add a permission > Microsoft Graph > Application permissions:
#      User.Invite.All, User.Read.All, Group.ReadWrite.All
#    - Click "Grant admin consent" for your tenant
# 3) Create a client secret:
#    - Certificates & secrets > New client secret; copy the Value (secret)
# 4) Set environment variables before running this script:
#    export TENANT_ID="<your-tenant-id>"
#    export CLIENT_ID="<your-app-client-id>"
#    export CLIENT_SECRET="<your-client-secret>"
#    # The script will request a token at runtime using these.
# 5) (Optional) Manually fetch and inspect a token:
#    token_resp="$(curl -sS -X POST \
#      -H 'Content-Type: application/x-www-form-urlencoded' \
#      --data "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default" \
#      "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token")"
#    echo "$token_resp" | jq -r '.access_token' | cut -c1-40
#    # Or set it for this script:
#    export GRAPH_TOKEN="$(echo "$token_resp" | jq -r '.access_token')"
#
# Alternative (delegated token; only if your signed-in app has consent to required scopes):
# - Ensure the enterprise app you use to get tokens has delegated scopes:
#   Group.ReadWrite.All and User.Invite.All (admin consent required).
# - Example with Azure CLI:
#   az login --tenant "<your-tenant-id>"
#   export GRAPH_TOKEN="$(az account get-access-token --resource-type ms-graph --query accessToken -o tsv)"
# - Then run this script without CLIENT_ID/CLIENT_SECRET; it will use GRAPH_TOKEN.
#
# Notes:
# - External collaboration must be allowed in tenant settings for invitations to succeed.
# - Least privilege: if you never invite, you can omit User.Invite.All; if you only invite and don’t add to groups, you can omit Group.ReadWrite.All.
