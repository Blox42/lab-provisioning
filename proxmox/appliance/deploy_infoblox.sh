#!/usr/bin/env bash
set -euo pipefail

# deploy_infoblox.sh — Provision an Infoblox appliance VM on Proxmox via API (no qm/pveum)

usage() {
  cat <<EOF
Usage: $0 --node NODE --storage STORAGE --iso-name NAME.iso [--iso-path /local/file.iso] \
          --vm-name NAME [--vmid N] [--memory 4096] [--cores 2] [--sockets 1] \
          [--disk-gb 60] [--net-model virtio] [--bridge vmbr0] [--vlan 42] [--start]

Auth (env):
  Token (recommended): PVE_USER, PVE_TOKEN_NAME, PVE_TOKEN_VALUE
  Password fallback:   PVE_USER, PVE_PASSWORD
Endpoint (env):
  PROXMOX_API_URL (https://host:8006/api2/json) or PROXMOX_HOST (host[:port])
  PROXMOX_INSECURE=1 to skip TLS verification (default 1)
EOF
}

require() { command -v "$1" >/dev/null 2>&1 || { echo "Error: missing dependency: $1" >&2; exit 2; }; }
require curl; require jq

# Defaults
NODE=""
STORAGE=""
ISO_NAME=""
ISO_PATH=""
VM_NAME=""
VMID=""
MEMORY_MB=4096
CORES=2
SOCKETS=1
DISK_GB=60
NET_MODEL="virtio"
BRIDGE="vmbr0"
VLAN_TAG=""
START_AFTER=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --node) NODE="$2"; shift 2;;
    --storage) STORAGE="$2"; shift 2;;
    --iso-name) ISO_NAME="$2"; shift 2;;
    --iso-path) ISO_PATH="$2"; shift 2;;
    --vm-name) VM_NAME="$2"; shift 2;;
    --vmid) VMID="$2"; shift 2;;
    --memory) MEMORY_MB="$2"; shift 2;;
    --cores) CORES="$2"; shift 2;;
    --sockets) SOCKETS="$2"; shift 2;;
    --disk-gb) DISK_GB="$2"; shift 2;;
    --net-model) NET_MODEL="$2"; shift 2;;
    --bridge) BRIDGE="$2"; shift 2;;
    --vlan) VLAN_TAG="$2"; shift 2;;
    --start) START_AFTER=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1;;
  esac
done

if [[ -z "$NODE" || -z "$STORAGE" || -z "$ISO_NAME" || -z "$VM_NAME" ]]; then
  echo "Error: --node, --storage, --iso-name, and --vm-name are required." >&2
  usage; exit 1
fi

# API base URL
PROXMOX_API_URL="${PROXMOX_API_URL:-}"
if [[ -z "$PROXMOX_API_URL" ]]; then
  host="${PROXMOX_HOST:-127.0.0.1}"
  [[ "$host" == *:* ]] || host="${host}:8006"
  PROXMOX_API_URL="https://${host}/api2/json"
fi

CURL_COMMON=("-sS")
[[ "${PROXMOX_INSECURE:-1}" == "1" ]] && CURL_COMMON+=("-k")

first_nonempty() { for x in "$@"; do [[ -n "${x:-}" ]] && { printf "%s" "$x"; return 0; }; done; return 1; }
urlencode() { local i c e out=""; for (( i=0; i<${#1}; i++ )); do c=${1:$i:1}; case "$c" in [a-zA-Z0-9_.~-]) out+="$c";; ' ') out+="+";; *) printf -v e '%%%02X' "'${c}"; out+="$e";; esac; done; printf '%s' "$out"; }

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
  elif [[ -n "$PVE_USER" && -n "$PVE_PASSWORD" ]]; then
    local resp ticket
    resp=$(curl "${CURL_COMMON[@]}" -X POST -H 'Content-Type: application/x-www-form-urlencoded' \
      --data-urlencode "username=${PVE_USER}" --data-urlencode "password=${PVE_PASSWORD}" \
      "${PROXMOX_API_URL}/access/ticket")
    ticket=$(jq -r '.data.ticket // empty' <<<"$resp")
    CSRF_TOKEN=$(jq -r '.data.CSRFPreventionToken // empty' <<<"$resp")
    if [[ -z "$ticket" || -z "$CSRF_TOKEN" ]]; then
      echo "Error: failed to obtain Proxmox API ticket (check PVE_USER/PVE_PASSWORD)" >&2
      exit 4
    fi
    AUTH_COOKIES=("-b" "PVEAuthCookie=${ticket}")
    AUTH_HEADERS=("-H" "CSRFPreventionToken: ${CSRF_TOKEN}")
  else
    echo "Error: Set PVE_USER plus token (PVE_TOKEN_NAME/PVE_TOKEN_VALUE) or PVE_PASSWORD." >&2
    exit 4
  fi
}

api_get() { curl "${CURL_COMMON[@]}" "${AUTH_HEADERS[@]}" "${AUTH_COOKIES[@]}" "${PROXMOX_API_URL}$1"; }
api_post() { local path="$1"; shift; curl "${CURL_COMMON[@]}" "${AUTH_HEADERS[@]}" "${AUTH_COOKIES[@]}" -X POST -H 'Content-Type: application/x-www-form-urlencoded' --data "$*" "${PROXMOX_API_URL}${path}"; }
api_put() { local path="$1"; shift; curl "${CURL_COMMON[@]}" "${AUTH_HEADERS[@]}" "${AUTH_COOKIES[@]}" -X PUT  -H 'Content-Type: application/x-www-form-urlencoded' --data "$*" "${PROXMOX_API_URL}${path}"; }
api_upload_iso() { # node, storage, iso_path
  local node="$1" storage="$2" fpath="$3"
  curl "${CURL_COMMON[@]}" "${AUTH_HEADERS[@]}" "${AUTH_COOKIES[@]}" \
    -X POST "${PROXMOX_API_URL}/nodes/${node}/storage/${storage}/upload" \
    -F content=iso -F "filename=@${fpath}"
}

api_login_if_needed

echo "==> Using Proxmox API at: ${PROXMOX_API_URL}"
echo "==> Target node: ${NODE}, storage: ${STORAGE}"

# VMID allocation
if [[ -z "$VMID" ]]; then
  VMID=$(api_get "/cluster/nextid" | jq -r '.data')
  [[ -n "$VMID" ]] || { echo "Error: failed to obtain next VMID" >&2; exit 5; }
  echo "==> Allocated VMID: $VMID"
else
  echo "==> Using provided VMID: $VMID"
fi

# Check or upload ISO
echo "==> Ensuring ISO '${ISO_NAME}' exists on storage '${STORAGE}'"
content_json=$(api_get "/nodes/${NODE}/storage/${STORAGE}/content")
have_iso=$(jq -r --arg name "$ISO_NAME" '.data[]?|select(.content=="iso")|.volid | select(endswith("/iso/"+$name))' <<<"$content_json" | head -n1 || true)
if [[ -z "$have_iso" ]]; then
  if [[ -n "$ISO_PATH" && -f "$ISO_PATH" ]]; then
    echo "==> Uploading ISO from ${ISO_PATH} ... (this may take a while)"
    api_upload_iso "$NODE" "$STORAGE" "$ISO_PATH" >/dev/null
    # Recheck
    content_json=$(api_get "/nodes/${NODE}/storage/${STORAGE}/content")
    have_iso=$(jq -r --arg name "$ISO_NAME" '.data[]?|select(.content=="iso")|.volid | select(endswith("/iso/"+$name))' <<<"$content_json" | head -n1 || true)
    [[ -n "$have_iso" ]] || { echo "Error: ISO upload seems to have failed (not visible as ${ISO_NAME})" >&2; exit 6; }
  else
    echo "Error: ISO '${ISO_NAME}' not found on storage and no valid --iso-path provided." >&2
    exit 6
  fi
else
  echo "==> ISO exists: ${have_iso}"
fi

# Create VM
echo "==> Creating VM ${VM_NAME} (VMID ${VMID})"
net_params="${NET_MODEL},bridge=${BRIDGE}"
[[ -n "$VLAN_TAG" ]] && net_params+=",tag=${VLAN_TAG}"

create_data=()
create_data+=("vmid=$(urlencode "$VMID")")
create_data+=("name=$(urlencode "$VM_NAME")")
create_data+=("memory=$(urlencode "$MEMORY_MB")")
create_data+=("cores=$(urlencode "$CORES")")
create_data+=("sockets=$(urlencode "$SOCKETS")")
create_data+=("scsihw=$(urlencode "virtio-scsi-pci")")
create_data+=("scsi0=$(urlencode "${STORAGE}:${DISK_GB}")")
create_data+=("net0=$(urlencode "$net_params")")
create_data+=("ide2=$(urlencode "${STORAGE}:iso/${ISO_NAME},media=cdrom")")
create_data+=("ostype=$(urlencode "l26")")
create_data+=("boot=$(urlencode "order=ide2;scsi0;net0")")

resp_create=$(api_post "/nodes/${NODE}/qemu" "${create_data[*]// /&}")
upid=$(jq -r '.data // empty' <<<"$resp_create")
if [[ -z "$upid" ]]; then
  echo "Warning: VM create response did not include UPID; response below:" >&2
  echo "$resp_create" >&2
fi

echo "==> VM ${VM_NAME} (${VMID}) created."

if [[ $START_AFTER -eq 1 ]]; then
  echo "==> Starting VM ${VMID}"
  start_resp=$(api_post "/nodes/${NODE}/qemu/${VMID}/status/start" "")
  echo "Start response: $(jq -r '.data // "ok"' <<<"$start_resp" 2>/dev/null || echo ok)"
fi

echo "Done. VMID=${VMID} NAME=${VM_NAME} NODE=${NODE} STORAGE=${STORAGE}"

