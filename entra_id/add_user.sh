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

set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 -u USER_PRINCIPAL_NAME [-n DISPLAY_NAME] [-t TENANT_ID] [-r INVITE_REDIRECT_URL]
    -u USER_PRINCIPAL_NAME  User principal name or email (e.g. user@domain.com) (required)
    -n DISPLAY_NAME         Display name for invitations (optional)
    -t TENANT_ID            Tenant ID to target (optional; required for client credentials auth)
    -r INVITE_REDIRECT_URL  Redirect URL for invitation (default: https://myapps.microsoft.com)

Authentication:
  - Provide a pre-acquired token in env GRAPH_TOKEN
  - OR provide CLIENT_ID, CLIENT_SECRET and TENANT_ID env vars (client credentials flow)
EOF
    exit 1
}

# defaults
TENANT_ID="${TENANT_ID:-}"
DISPLAY_NAME=""
INVITE_REDIRECT_URL="https://myapps.microsoft.com"

export $(grep -v '^#' .env | xargs)


while getopts ":u:n:t:r:" opt; do
    case ${opt} in
        u) UPN="${OPTARG}" ;;
        n) DISPLAY_NAME="${OPTARG}" ;;
        t) TENANT_ID="${OPTARG}" ;;
        r) INVITE_REDIRECT_URL="${OPTARG}" ;;
        *) usage ;;
    esac
done

if [ -z "${UPN:-}" ]; then
    usage
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required but not installed." >&2
    exit 2
fi

# Acquire token: prefer GRAPH_TOKEN, else use client credentials if CLIENT_ID & CLIENT_SECRET & TENANT_ID provided.
TOKEN=""
get_token() {
    if [ -n "${GRAPH_TOKEN:-}" ]; then
        TOKEN="$GRAPH_TOKEN"
        return 0
    fi

    if [ -n "${CLIENT_ID:-}" ] && [ -n "${CLIENT_SECRET:-}" ] && [ -n "${TENANT_ID:-}" ]; then
        token_url="https://login.microsoftonline.com/$TENANT_ID/oauth2/v2.0/token"
        resp="$(curl -sS -X POST -H 'Content-Type: application/x-www-form-urlencoded' --data "grant_type=client_credentials&client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default" "$token_url")" || {
                echo "Failed to request token from AAD." >&2
                echo "$resp" >&2
                return 1
            }
        TOKEN="$(printf '%s' "$resp" | jq -r '.access_token // empty')"
        if [ -z "$TOKEN" ]; then
            echo "Failed to obtain access token. Response:" >&2
            echo "$resp" | jq -r '.' >&2 || echo "$resp" >&2
            return 1
        fi
        return 0
    fi

    echo "No authentication method configured. Set GRAPH_TOKEN or CLIENT_ID, CLIENT_SECRET and TENANT_ID." >&2
    return 1
}

# graph_request: method uri [body]
# prints body to stdout and sets HTTP_STATUS global var
HTTP_STATUS=0
graph_request() {
    local method="$1"; local uri="$2"; local body="${3:-}"
    local curl_out
    if [ -n "$body" ]; then
        curl_out="$(curl -sS -X "$method" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            --data "$body" \
            "$uri" --write-out "\n%{http_code}")" || return 1
    else
        curl_out="$(curl -sS -X "$method" \
            -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type: application/json" \
            "$uri" --write-out "\n%{http_code}")" || return 1
    fi
    HTTP_STATUS="$(printf '%s' "$curl_out" | tail -n1)"
    printf '%s' "$curl_out" | sed '$d'
    return 0
}

# ensure token
if ! get_token; then
    exit 3
fi

# wrapper that retries once on 401 if token can be refreshed via client credentials
graph_get() {
    local uri="$1"
    local out
    out="$(graph_request GET "$uri")" || {
        echo "Graph GET request failed for $uri" >&2
        return 1
    }
    if [ "$HTTP_STATUS" = "401" ] && [ -n "${CLIENT_ID:-}" ] && [ -n "${CLIENT_SECRET:-}" ] && [ -n "${TENANT_ID:-}" ]; then
        if get_token; then
            out="$(graph_request GET "$uri")" || {
                echo "Graph GET retry failed for $uri" >&2
                return 1
            }
        fi
    fi
    if [ "$HTTP_STATUS" -ge 400 ]; then
        printf '%s\n' "$out" >&2
    fi
    printf '%s' "$out"
}

graph_post() {
    local uri="$1"; local body="$2"
    local out
    out="$(graph_request POST "$uri" "$body")" || {
        echo "Graph POST request failed for $uri" >&2
        return 1
    }
    if [ "$HTTP_STATUS" = "401" ] && [ -n "${CLIENT_ID:-}" ] && [ -n "${CLIENT_SECRET:-}" ] && [ -n "${TENANT_ID:-}" ]; then
        if get_token; then
            out="$(graph_request POST "$uri" "$body")" || {
                echo "Graph POST retry failed for $uri" >&2
                return 1
            }
        fi
    fi
    printf '%s' "$out"
}

# 1) Check if user exists by userPrincipalName
# URL-encode OData $filter to avoid curl "Malformed input" errors (spaces/quotes must be encoded)
filter_users="$(printf "mail eq '%s'" "$UPN" | jq -sRr @uri)"
uri_users="https://graph.microsoft.com/v1.0/users?\$filter=$filter_users"
resp_users="$(graph_get "$uri_users")"
userId="$(echo "$resp_users" | jq -r '.value[0].id // empty')"
userPrincipalNameFound="$(echo "$resp_users" | jq -r '.value[0].userPrincipalName // empty')"
userDisplayNameFound="$(echo "$resp_users" | jq -r '.value[0].displayName // empty')"

if [ -n "$userId" ]; then
    echo "User exists: $userPrincipalNameFound (id: $userId, displayName: $userDisplayNameFound)"
else
    echo "User $UPN not found. Creating invite for external user..."
    # build invite body
    read -r -d '' INVITE_BODY <<EOF || true
{
  "invitedUserEmailAddress": "$(printf '%s' "$UPN" | sed 's/"/\\"/g')",
  "inviteRedirectUrl": "$(printf '%s' "$INVITE_REDIRECT_URL" | sed 's/"/\\"/g')",
  "sendInvitationMessage": true$( [ -n "$DISPLAY_NAME" ] && printf ',\n  "invitedUserDisplayName": "%s"' "$(printf '%s' "$DISPLAY_NAME" | sed 's/"/\\"/g')" || true )
}
EOF

    invite_resp="$(graph_post "https://graph.microsoft.com/v1.0/invitations" "$INVITE_BODY")" || {
        echo "Failed to send invitation. Response:" >&2
        echo "$invite_resp" >&2
        exit 5
    }
    echo "Invitation sent. Response:"
    echo "$invite_resp" | jq -r '. | {id: .id, invitedUserDisplayName: .invitedUserDisplayName, invitedUserEmailAddress: .invitedUserEmailAddress, status: .status}' 2>/dev/null || echo "$invite_resp"

    # re-query user (the guest user may take a short time to appear)
    echo "Waiting for invited user to appear in directory..."
    attempts=0
    until [ "$attempts" -ge 6 ]; do
        sleep 3
        resp_users="$(graph_get "$uri_users")"
        userId="$(echo "$resp_users" | jq -r '.value[0].id // empty')"
        if [ -n "$userId" ]; then
            userPrincipalNameFound="$(echo "$resp_users" | jq -r '.value[0].userPrincipalName // empty')"
            userDisplayNameFound="$(echo "$resp_users" | jq -r '.value[0].displayName // empty')"
            echo "User found: $userPrincipalNameFound (id: $userId)"
            break
        fi
        attempts=$((attempts + 1))
    done

    if [ -z "$userId" ]; then
        echo "Invited user did not appear in the directory after waiting." >&2
        exit 6
    fi
fi
# 2) Find group "all-admins"
filter_groups="$(printf "displayName eq '%s'" "all-admins" | jq -sRr @uri)"
group_filter="https://graph.microsoft.com/v1.0/groups?\$filter=$filter_groups"
group_resp="$(graph_get "$group_filter")"

# If the Graph call returned an error (e.g., insufficient privileges), surface it clearly and stop.
if echo "$group_resp" | jq -e 'type=="object" and has("error")' >/dev/null 2>&1; then
    errCode="$(echo "$group_resp" | jq -r '.error.code // "UnknownError"')"
    errMsg="$(echo "$group_resp" | jq -r '.error.message // "Unknown error"')"
    echo "Graph API error while querying groups: $errCode - $errMsg" >&2
    echo "Ensure your token has Microsoft Graph permissions: Group.Read.All or Group.ReadWrite.All with admin consent." >&2
    exit 7
fi

groupId="$(echo "$group_resp" | jq -r '.value[0].id // empty')"
groupDisplayName="$(echo "$group_resp" | jq -r '.value[0].displayName // empty')"

if [ -z "$groupId" ]; then
    echo "Group 'all-admins' not found in tenant." >&2
    exit 7
fi

echo "Group found: $groupDisplayName (id: $groupId)"

# 3) Check membership
members_uri="https://graph.microsoft.com/v1.0/groups/$groupId/members?\$select=id"
members_resp="$(graph_get "$members_uri")"
is_member="$(echo "$members_resp" | jq -r --arg uid "$userId" '.value[]?.id | select(. == $uid) // empty')"

if [ -n "$is_member" ]; then
    echo "User (id: $userId) is already a member of 'all-admins'."
else
    echo "Adding user (id: $userId) to group 'all-admins'..."
    add_body="$(jq -n --arg id "https://graph.microsoft.com/v1.0/directoryObjects/$userId" '{ "@odata.id": $id }')"
    add_resp="$(graph_post "https://graph.microsoft.com/v1.0/groups/$groupId/members/\$ref" "$add_body")" || {
        echo "Failed to add user to group. Response:" >&2
        echo "$add_resp" >&2
        exit 8
    }
    echo "User added to group 'all-admins'."
fi

# minimal output
echo "Result:"
echo " userId: $userId"
echo " userPrincipalName: ${userPrincipalNameFound:-$UPN}"
echo " displayName: ${userDisplayNameFound:-$DISPLAY_NAME}"
echo " groupId: $groupId"

exit 0