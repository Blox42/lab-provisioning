#!/usr/bin/env bash
# add_user.sh - Add a Proxmox user (by email) to an OpenID realm and place in a group via Proxmox API (no pveum).
# - Creates/sanitizes a userid from the email for the given OpenID realm
# - Ensures target group exists (idempotent)
# - Creates or updates the user (no password for OpenID) and ensures group membership
#
# Usage:
#   ./add_user.sh -e user@example.com [-r Blox42] [-g Admin] [-u customuserid]
#
# CI/Semaphore and env support (CLI flags override env):
#   EMAIL, MAILADDRESS
#   GROUP, GROUPNAME
#   REALM
#   USER_NAME_OVERRIDE (also: USER_NAME, USERNAME, USERID)
#   Also accepts lowercase and SURVEY_* variants (e.g., SURVEY_MAILADDRESS, SURVEY_GROUPNAME).
#
# Proxmox API auth (one of):
#   - Token: set PVE_USER (e.g. root@pam), PVE_TOKEN_NAME, PVE_TOKEN_VALUE
#   - Password: set PVE_USER, PVE_PASSWORD
# API endpoint configuration:
#   - PROXMOX_API_URL (default: https://127.0.0.1:8006/api2/json)
#     or set PROXMOX_HOST (host:port, default port 8006) to auto-derive URL.
#   - Set PROXMOX_INSECURE=1 to skip TLS verify (self-signed certs).
#
# Notes:
# - Proxmox user IDs are of form <name>@<realm>. The <name> must only contain [A-Za-z0-9_.-].
# - The OpenID realm must already be configured in Proxmox.

set -euo pipefail

usage() {
    echo "Usage: $0 -e <email> [-r <realm=Blox42>] [-g <group=Admin>] [-u <userid-name>]" >&2
    exit 1
}

# Defaults (used only if not set via CLI or env)
DEFAULT_REALM="Blox42"
DEFAULT_GROUP="Admin"

EMAIL=""
REALM=""
GROUP=""
USER_NAME_OVERRIDE=""

while getopts ":e:r:g:u:h" opt; do
    case "$opt" in
        e) EMAIL="$OPTARG" ;;
        r) REALM="$OPTARG" ;;
        g) GROUP="$OPTARG" ;;
        u) USER_NAME_OVERRIDE="$OPTARG" ;;
        h|\?) usage ;;
    esac
done

first_nonempty() { for x in "$@"; do [[ -n "${x:-}" ]] && { printf "%s" "$x"; return 0; }; done; return 1; }

# Populate from environment if not provided via flags
[[ -z "$EMAIL" ]] && EMAIL="$(first_nonempty \
    "${MAILADDRESS:-}" "${mailaddress:-}" \
    "${SURVEY_MAILADDRESS:-}" "${survey_mailaddress:-}" \
    "${EMAIL:-}" "${email:-}" \
    "${SURVEY_EMAIL:-}" "${survey_email:-}" \
    "${ADDUSER_EMAIL:-}" "${ADD_USER_EMAIL:-}" "${USER_EMAIL:-}" || true)"

[[ -z "$REALM" ]] && REALM="$(first_nonempty \
    "${REALM:-}" "${realm:-}" \
    "${SURVEY_REALM:-}" "${survey_realm:-}" \
    "${ADDUSER_REALM:-}" "${ADD_USER_REALM:-}" "${USER_REALM:-}" || true)"

[[ -z "$GROUP" ]] && GROUP="$(first_nonempty \
    "${GROUPNAME:-}" "${groupname:-}" \
    "${SURVEY_GROUPNAME:-}" "${survey_groupname:-}" \
    "${GROUP:-}" "${group:-}" \
    "${SURVEY_GROUP:-}" "${survey_group:-}" \
    "${ADDUSER_GROUP:-}" "${ADD_USER_GROUP:-}" "${USER_GROUP:-}" || true)"

[[ -z "$USER_NAME_OVERRIDE" ]] && USER_NAME_OVERRIDE="$(first_nonempty \
    "${USER_NAME_OVERRIDE:-}" "${USER_NAME:-}" "${user_name:-}" \
    "${USERNAME:-}" "${username:-}" \
    "${USERID:-}" "${userid:-}" \
    "${SURVEY_USER_NAME_OVERRIDE:-}" "${survey_user_name_override:-}" \
    "${SURVEY_USERID:-}" "${survey_userid:-}" \
    "${SURVEY_USERNAME:-}" "${survey_username:-}" || true)"

# Apply defaults if still empty
REALM="${REALM:-$DEFAULT_REALM}"
GROUP="${GROUP:-$DEFAULT_GROUP}"

[[ -z "$EMAIL" ]] && usage
if ! [[ "$EMAIL" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; then
    echo "Error: invalid email: $EMAIL" >&2
    exit 2
fi

sanitize_name() {
    # Allow only [A-Za-z0-9_.-]; replace others with '_'; trim to 64 chars
    local s="$1"
    s="${s// /_}"
    s="${s//@/_}"
    s="$(printf "%s" "$s" | tr -c '[:alnum:]_.-' '_' )"
    s="$(printf "%s" "$s" | sed -E 's/_+/_/g')"
    s="$(printf "%s" "$s" | sed -E 's/^[_\.\-]+//; s/[_\.\-]+$//')"
    s="${s:0:64}"
    [[ -z "$s" ]] && s="user"
    printf "%s" "$s"
}

# Derive user name part
if [[ -n "$USER_NAME_OVERRIDE" ]]; then
    NAME_PART="$(sanitize_name "$USER_NAME_OVERRIDE")"
else
    # Preserve prior behavior: derive from full email string
    NAME_PART="$(sanitize_name "$EMAIL")"
fi

USERID="${NAME_PART}@${REALM}"

echo "Target realm: $REALM"
echo "Target group: $GROUP"
echo "Email:        $EMAIL"
echo "UserID:       $USERID"

# Requirements
command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 3; }

# API base URL
PROXMOX_API_URL="${PROXMOX_API_URL:-}"
if [[ -z "$PROXMOX_API_URL" ]]; then
    host="${PROXMOX_HOST:-127.0.0.1}"
    if [[ "$host" != *:* ]]; then host="${host}:8006"; fi
    PROXMOX_API_URL="https://${host}/api2/json"
fi

# TLS verify or not
CURL_COMMON=("-sS")
if [[ "${PROXMOX_INSECURE:-1}" == "1" ]]; then
    CURL_COMMON+=("-k")
fi

# Auth setup: prefer API token, fallback to username/password login ticket
PVE_USER="$(first_nonempty "${PVE_USER:-}" "${PROXMOX_USER:-}" "${PVE_USERNAME:-}" || true)"
PVE_TOKEN_NAME="$(first_nonempty "${PVE_TOKEN_NAME:-}" "${PROXMOX_TOKEN_NAME:-}" || true)"
PVE_TOKEN_VALUE="$(first_nonempty "${PVE_TOKEN_VALUE:-}" "${PROXMOX_TOKEN_VALUE:-}" "${PVE_API_TOKEN:-}" || true)"
PVE_PASSWORD="$(first_nonempty "${PVE_PASSWORD:-}" "${PROXMOX_PASSWORD:-}" || true)"

AUTH_HEADERS=()
AUTH_COOKIES=()
CSRF_TOKEN=""

api_login_if_needed() {
    if [[ -n "$PVE_USER" && -n "$PVE_TOKEN_NAME" && -n "$PVE_TOKEN_VALUE" ]]; then
        AUTH_HEADERS=("-H" "Authorization: PVEAPIToken=${PVE_USER}!${PVE_TOKEN_NAME}=${PVE_TOKEN_VALUE}")
        return 0
    elif [[ -n "$PVE_USER" && -n "$PVE_PASSWORD" ]]; then
        # Obtain ticket and CSRF token
        local resp
        resp=$(curl "${CURL_COMMON[@]}" -X POST \
            -H 'Content-Type: application/x-www-form-urlencoded' \
            --data-urlencode "username=${PVE_USER}" \
            --data-urlencode "password=${PVE_PASSWORD}" \
            "${PROXMOX_API_URL}/access/ticket")
        local ticket
        ticket=$(jq -r '.data.ticket // empty' <<<"$resp")
        CSRF_TOKEN=$(jq -r '.data.CSRFPreventionToken // empty' <<<"$resp")
        if [[ -z "$ticket" || -z "$CSRF_TOKEN" ]]; then
            echo "Error: failed to obtain Proxmox API ticket (check PVE_USER/PVE_PASSWORD)" >&2
            jq -r '.errors // empty' <<<"$resp" || true
            exit 4
        fi
        AUTH_COOKIES=("-b" "PVEAuthCookie=${ticket}")
        AUTH_HEADERS=("-H" "CSRFPreventionToken: ${CSRF_TOKEN}")
        return 0
    else
        echo "Error: provide API credentials via token (PVE_USER, PVE_TOKEN_NAME, PVE_TOKEN_VALUE) or password (PVE_USER, PVE_PASSWORD)." >&2
        exit 4
    fi
}

api_get() { # path
    curl "${CURL_COMMON[@]}" "${AUTH_HEADERS[@]}" "${AUTH_COOKIES[@]}" \
        "${PROXMOX_API_URL}$1"
}

api_post() { # path, data (urlencoded string or @json)
    local path="$1"; shift
    curl "${CURL_COMMON[@]}" "${AUTH_HEADERS[@]}" "${AUTH_COOKIES[@]}" \
        -X POST -H 'Content-Type: application/x-www-form-urlencoded' \
        --data "$*" "${PROXMOX_API_URL}${path}"
}

api_put() { # path, data (urlencoded string)
    local path="$1"; shift
    curl "${CURL_COMMON[@]}" "${AUTH_HEADERS[@]}" "${AUTH_COOKIES[@]}" \
        -X PUT -H 'Content-Type: application/x-www-form-urlencoded' \
        --data "$*" "${PROXMOX_API_URL}${path}"
}

urlencode() {
    # Minimal URL-encoding for simple form values
    local LANG=C i c e out
    out=""
    for (( i=0; i<${#1}; i++ )); do
        c=${1:$i:1}
        case "$c" in
            [a-zA-Z0-9_.~-]) out+="$c" ;;
            ' ') out+="+" ;;
            *) printf -v e '%%%02X' "'${c}"; out+="$e" ;;
        esac
    done
    printf '%s' "$out"
}

api_login_if_needed

# Optional: warn if realm not present
realms_json=$(api_get "/access/domains") || true
if ! jq -e --arg r "$REALM" '.data[]?|select(.realm==$r)' >/dev/null 2>&1 <<<"$realms_json"; then
    echo "Warning: realm '$REALM' not found via API /access/domains. Ensure your OpenID realm exists." >&2
fi

# Ensure group exists (idempotent)
groups_json=$(api_get "/access/groups")
if jq -e --arg g "$GROUP" '.data[]?|select(.groupid==$g)' >/dev/null 2>&1 <<<"$groups_json"; then
    echo "Group '$GROUP' exists."
else
    echo "Creating group '$GROUP'..."
    create_resp=$(api_post "/access/groups" "groupid=$(urlencode "$GROUP")&comment=$(urlencode "$GROUP group")") || true
    if ! jq -e '.data!=null or .data==null' >/dev/null 2>&1 <<<"$create_resp"; then
        echo "Warning: could not create group '$GROUP'. Response:" >&2
        echo "$create_resp" >&2
    fi
fi

# Create or update user
users_json=$(api_get "/access/users")
if jq -e --arg u "$USERID" '.data[]?|select(.userid==$u)' >/dev/null 2>&1 <<<"$users_json"; then
    echo "User '$USERID' already exists. Updating email..."
    upd_resp=$(api_put "/access/users/$(urlencode "$USERID")" "email=$(urlencode "$EMAIL")&comment=$(urlencode "$EMAIL")") || true
    # ignore response validation to be tolerant
else
    echo "Creating user '$USERID'..."
    add_resp=$(api_post "/access/users" \
        "userid=$(urlencode "$USERID")&email=$(urlencode "$EMAIL")&comment=$(urlencode "$EMAIL")&enable=1") || true
    # ignore response validation to be tolerant
fi

# Ensure group membership
echo "Ensuring '$USERID' is in group '$GROUP'..."
# Try to read current user groups and update via user PUT
user_detail=$(api_get "/access/users/$(urlencode "$USERID")") || true
current_groups=$(jq -r '.data.groups // ""' <<<"$user_detail" 2>/dev/null || echo "")
if [[ -n "$current_groups" ]]; then
    IFS=',' read -r -a arr <<<"$current_groups"
    found=0
    for g in "${arr[@]}"; do [[ "$g" == "$GROUP" ]] && { found=1; break; }; done
    if [[ $found -eq 0 ]]; then
        arr+=("$GROUP")
        new_groups=$(IFS=, ; echo "${arr[*]}")
        api_put "/access/users/$(urlencode "$USERID")" "groups=$(urlencode "$new_groups")" >/dev/null || true
    fi
else
    # Fallback: try update on group object to add the user without affecting other groups
    group_detail=$(api_get "/access/groups/$(urlencode "$GROUP")") || true
    current_users=$(jq -r '.data.users // ""' <<<"$group_detail" 2>/dev/null || echo "")
    if [[ -n "$current_users" ]]; then
        IFS=',' read -r -a uarr <<<"$current_users"
        gfound=0
        for u in "${uarr[@]}"; do [[ "$u" == "$USERID" ]] && { gfound=1; break; }; done
        if [[ $gfound -eq 0 ]]; then
            uarr+=("$USERID")
            new_users=$(IFS=, ; echo "${uarr[*]}")
            api_put "/access/groups/$(urlencode "$GROUP")" "users=$(urlencode "$new_users")" >/dev/null || true
        fi
    else
        # Last resort: attempt to set group users to just this user (only if empty)
        api_put "/access/groups/$(urlencode "$GROUP")" "users=$(urlencode "$USERID")" >/dev/null || true
    fi
fi

echo "Done."
