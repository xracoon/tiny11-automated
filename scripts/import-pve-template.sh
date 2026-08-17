#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# import-pve-template.sh — Import a nano11 qcow2 candidate into Proxmox VE
#
# Usage:
#   ./scripts/import-pve-template.sh <vmid> <candidate.qcow2> <storage> <bridge> [name] [OPTIONS]
#
# Positional arguments (required):
#   vmid              VM ID
#   candidate.qcow2   Path to the qcow2 image
#   storage           PVE storage target (e.g. local-lvm)
#   bridge            Network bridge (e.g. vmbr0, vnetnas)
#   name              VM name (default: tiny11-pve-candidate)
#
# Optional named arguments:
#   --cores N         CPU cores (default: 2)
#   --memory N        Memory in MB (default: 4096)
#   --balloon N       Balloon memory in MB (default: 2048)
#   --machine TYPE    Machine type (default: q35)
#   --cipassword PASS Set the Administrator password through ConfigDrive2
#   --no-cloudinit    Skip cloud-init disk attachment
#   --template        Convert to template after import (default: keep as VM)
#   --tpm             Add TPM 2.0 state disk
# ---------------------------------------------------------------------------

usage() {
  sed -n '/^# Usage:/,/^# ---/p' "$0" | sed 's/^# \?//' >&2
  exit 2
}

# --- Parse positional arguments ------------------------------------------------

[[ $# -ge 4 ]] || usage

vmid="$1";      shift
image="$1";     shift
storage="$1";   shift
bridge="$1";    shift
name="tiny11-pve-candidate"
if [[ $# -gt 0 && "$1" != --* ]]; then
  name="$1"
  shift
fi

# --- Defaults for optional parameters -----------------------------------------

cores=2
memory=4096
balloon=2048
machine="q35"
do_cloudinit=true
do_template=false
do_tpm=false
cipassword=""

# --- Parse optional named arguments -------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cores)       cores="$2";      shift 2 ;;
    --memory)      memory="$2";     shift 2 ;;
    --balloon)     balloon="$2";    shift 2 ;;
    --machine)     machine="$2";    shift 2 ;;
    --cipassword)  [[ $# -ge 2 ]] || { echo "--cipassword requires a value" >&2; exit 2; }; cipassword="$2"; shift 2 ;;
    --no-cloudinit) do_cloudinit=false; shift ;;
    --template)     do_template=true;  shift ;;
    --tpm)         do_tpm=true;     shift ;;
    -h|--help)     usage ;;
    *)             echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

# --- Validate inputs ----------------------------------------------------------

[[ "$vmid" =~ ^[1-9][0-9]*$ ]] || { echo "VMID must be a positive integer" >&2; exit 2; }
[[ -f "$image" ]]              || { echo "Image not found: $image" >&2; exit 2; }
[[ -f "$image.sha256" ]]       || { echo "Checksum file not found: $image.sha256" >&2; exit 2; }
if ! $do_cloudinit && [[ -n "$cipassword" ]]; then
  echo "--cipassword requires cloud-init; remove --no-cloudinit" >&2
  exit 2
fi
(cd "$(dirname "$image")" && sha256sum -c "$(basename "$image").sha256")

# --- Create VM ----------------------------------------------------------------

echo ">>> Creating VM $vmid ($name)..."
qm create "$vmid" --name "$name" --machine "$machine" --bios ovmf --ostype win11 \
  --cpu host --cores "$cores" --memory "$memory" --balloon "$balloon" \
  --agent enabled=1,fstrim_cloned_disks=1 \
  --scsihw virtio-scsi-single --net0 "virtio,bridge=$bridge" --serial0 socket

# --- EFI disk -----------------------------------------------------------------

echo ">>> Creating EFI disk..."
qm set "$vmid" --efidisk0 "$storage:1,efitype=4m,pre-enrolled-keys=1"

# --- Import qcow2 -----------------------------------------------------------

echo ">>> Importing qcow2 disk..."
qm importdisk "$vmid" "$image" "$storage" --format qcow2

imported_volume="$(qm config "$vmid" | awk -F': ' '$1 == "unused0" { print $2 }' | cut -d, -f1)"
[[ -n "$imported_volume" ]] || { echo "ERROR: Could not resolve imported unused0 volume" >&2; exit 1; }

# --- Attach imported disk (split into two commands to avoid PVE 9 race) ------

echo ">>> Attaching imported disk as scsi0..."
qm set "$vmid" --scsi0 "$imported_volume,discard=on,iothread=1,ssd=1" --boot order=scsi0
qm set "$vmid" --delete unused0

# --- Cloud-init (optional) ----------------------------------------------------

if $do_cloudinit; then
  echo ">>> Adding cloud-init..."
  qm set "$vmid" --ide2 "$storage:cloudinit" --citype configdrive2 --ipconfig0 ip=dhcp
  if [[ -n "$cipassword" ]]; then
    qm set "$vmid" --cipassword "$cipassword"
  fi
fi

# --- TPM (optional) -----------------------------------------------------------

if $do_tpm; then
  echo ">>> Adding TPM 2.0..."
  qm set "$vmid" --tpmstate0 "$storage:1,version=v2.0"
fi

# --- Convert to template (optional) -------------------------------------------

if $do_template; then
  if [[ -z "$cipassword" ]]; then
    echo "WARNING: Template uses the default Administrator account with a blank password." >&2
    echo "         Use --cipassword for anything beyond isolated console testing." >&2
  fi
  echo ">>> Converting to template..."
  qm template "$vmid"
fi

# --- Summary ------------------------------------------------------------------

echo ""
echo "=== VM $vmid ($name) imported successfully ==="
qm config "$vmid"
echo ""
if $do_template; then
  echo "Clone with:  qm clone $vmid <newid> --name <name> [--full]"
fi
if [[ -z "$cipassword" ]]; then
  echo "Guest login: Administrator with a blank password (local console only)."
else
  echo "Guest login: Administrator with the ConfigDrive2 password supplied at import."
fi
