# Lab Provisioning

Collection of small, script-first utilities for lab automation.

- wireguard
  - Automates client provisioning in wireguard-ui, downloads configs/QR, and emails them.
  - See `lab-provisioning/wireguard/README.md` for setup and Docker usage.

- entra_id
  - Ensures a user exists in Microsoft Entra ID (invite if needed) and adds them to the "all-admins" group via Microsoft Graph.
  - See `lab-provisioning/entra_id/README.md`.

- proxmox/iam
  - Proxmox identity and access helpers using only the REST API (no `pveum`).
  - See `lab-provisioning/proxmox/iam/README.md`.

Common requirements across scripts: `curl`, `jq`. Some scripts may require extra tools noted in their README.
