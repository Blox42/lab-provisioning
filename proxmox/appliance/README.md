# Proxmox Appliance — Infoblox Deployment (API-only)

This module provides a script to deploy an Infoblox appliance VM on Proxmox using only the Proxmox REST API (no `qm`, no `pve*` CLIs).

- Uploads an ISO to a storage (if not already present)
- Creates a VM (VMID auto-allocated if not given)
- Attaches disk and network
- Mounts the ISO as CD-ROM and optionally starts the VM

## Requirements
- `curl`, `jq`
- A Proxmox account or API token with permissions to create/manage QEMU VMs and upload content.

## Quick Start
```
# Auth (recommended: token)
export PVE_USER="root@pam"
export PVE_TOKEN_NAME="ci"
export PVE_TOKEN_VALUE="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Endpoint
export PROXMOX_HOST="proxmox.example.com:8006"   # or PROXMOX_API_URL=https://host:8006/api2/json
export PROXMOX_INSECURE=1                          # skip TLS verify for self-signed certs

# Deployment
cd lab-provisioning/proxmox/appliance
./deploy_infoblox.sh \
  --node pve1 \
  --storage local \
  --iso-name infoblox-8.6.iso \
  --iso-path /path/to/infoblox-8.6.iso \
  --vm-name iblox-lab \
  --memory 8192 \
  --cores 4 \
  --disk-gb 100 \
  --bridge vmbr0 \
  --vlan 42 \
  --start
```

Notes:
- If the ISO already exists on the storage (visible in Proxmox), you can omit `--iso-path` and just set `--iso-name`.
- If you omit `--vmid`, the script fetches the next available VMID from the cluster.

## Arguments
- `--node`                Proxmox node name (e.g., `pve1`) [required]
- `--storage`             Target storage for ISO and disk (e.g., `local`, `local-lvm`) [required]
- `--iso-name`            ISO filename as it should appear on storage [required]
- `--iso-path`            Local path to ISO to upload (optional if already on storage)
- `--vm-name`             VM name (Proxmox display name) [required]
- `--vmid`                VMID (optional; auto-alloc if missing)
- `--memory`              RAM in MB (default 4096)
- `--cores`               vCPU cores (default 2)
- `--sockets`             vCPU sockets (default 1)
- `--disk-gb`             Disk size in GB (default 60)
- `--net-model`           NIC model (default `virtio`)
- `--bridge`              Bridge name (default `vmbr0`)
- `--vlan`                VLAN tag (optional)
- `--start`               Start VM after creation (optional flag)

## Auth via Environment
- Token (recommended): `PVE_USER`, `PVE_TOKEN_NAME`, `PVE_TOKEN_VALUE`
- Password (fallback): `PVE_USER`, `PVE_PASSWORD`
- Endpoint: `PROXMOX_API_URL` or `PROXMOX_HOST`; `PROXMOX_INSECURE=1` to skip TLS verification

## Caveats
- Infoblox appliances typically expect manual console setup after boot; this script focuses on provisioning the VM resources and media.
- Ensure the chosen storage supports ISO content and QEMU disks.
