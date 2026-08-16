#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
  echo "Usage: $0 <vmid> <candidate.qcow2> <storage> <bridge> [name]" >&2
  exit 2
fi

vmid="$1"
image="$2"
storage="$3"
bridge="$4"
name="${5:-tiny11-pve-candidate}"

[[ "$vmid" =~ ^[1-9][0-9]*$ ]] || { echo "VMID must be a positive integer" >&2; exit 2; }
[[ -f "$image" ]] || { echo "Image not found: $image" >&2; exit 2; }
[[ -f "$image.sha256" ]] || { echo "Checksum file not found: $image.sha256" >&2; exit 2; }
(cd "$(dirname "$image")" && sha256sum -c "$(basename "$image").sha256")

qm create "$vmid" --name "$name" --machine q35 --bios ovmf --ostype win11 \
  --cpu host --cores 2 --memory 4096 --balloon 2048 --agent enabled=1,fstrim_cloned_disks=1 \
  --scsihw virtio-scsi-single --net0 "virtio,bridge=$bridge" --serial0 socket
qm set "$vmid" --efidisk0 "$storage:1,efitype=4m,pre-enrolled-keys=1"
qm importdisk "$vmid" "$image" "$storage" --format qcow2
imported_volume="$(qm config "$vmid" | awk -F': ' '$1 == "unused0" { print $2 }' | cut -d, -f1)"
[[ -n "$imported_volume" ]] || { echo "Could not resolve the imported unused0 volume" >&2; exit 1; }
qm set "$vmid" --scsi0 "$imported_volume,discard=on,iothread=1,ssd=1" --delete unused0 --boot order=scsi0
qm set "$vmid" --ide2 "$storage:cloudinit" --citype configdrive2

echo "Candidate imported as VM $vmid. Add TPM only if your policy requires it:"
echo "  qm set $vmid --tpmstate0 $storage:1,version=v2.0"
echo "This helper does not assert that the guest has booted; perform the runtime checklist in docs/PVE.md."
