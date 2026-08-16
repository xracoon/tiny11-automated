# Tiny11 Automated — Proxmox VE Candidate Builder

[![Build Tiny11 PVE Candidate](https://github.com/kelexine/tiny11-automated/actions/workflows/build-tiny11.yml/badge.svg)](https://github.com/kelexine/tiny11-automated/actions/workflows/build-tiny11.yml)
[![Build Tiny11 Core PVE Candidate](https://github.com/kelexine/tiny11-automated/actions/workflows/build-tiny11-core.yml/badge.svg)](https://github.com/kelexine/tiny11-automated/actions/workflows/build-tiny11-core.yml)
[![Build Nano11 PVE Candidate](https://github.com/kelexine/tiny11-automated/actions/workflows/build-nano11.yml/badge.svg)](https://github.com/kelexine/tiny11-automated/actions/workflows/build-nano11.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

This branch builds minimized Windows 11 images for Proxmox VE. It retains the original three Standard, Core, and Nano build entry points, but produces compressed QCOW2 candidate disks instead of installer ISOs.

> These outputs are candidates, not pre-validated appliances. CI performs static image checks only. Boot behavior, PVE integration, and N5105 hardware compatibility must be verified on the target PVE node.

## Build variants

| Variant | Entry script | Output | Intended use |
|---|---|---|---|
| Standard | `scripts/tiny11maker-headless.ps1` | `tiny11-standard-pve-candidate.qcow2` | Most serviceable PVE guest |
| Core | `scripts/tiny11coremaker-headless.ps1` | `tiny11-core-pve-candidate.qcow2` | Reduced, less serviceable test guest |
| Nano | `scripts/nano11builder-headless.ps1` | `nano11-pve-candidate.qcow2` | Most aggressive VM-only experiment |

Nano is supported by the same build system but is not the implementation baseline. All three builders call the shared `PveTemplateBuilder` module for PVE-specific work. Nano receives VirtIO drivers after its DriverStore pruning.

## PVE image profile

Each candidate uses:

- Q35 machine type and OVMF/UEFI boot
- Secure Boot-compatible EFI layout
- dynamic 32 GiB virtual disk by default
- GPT with 260 MiB EFI, 16 MiB MSR, and the remaining space as NTFS
- DISM `/Apply-Image /Compact`
- compressed QCOW2 output
- VirtIO SCSI single, IO thread, and discard as the recommended disk configuration
- VirtIO network adapter
- QEMU Guest Agent and balloon support
- Cloudbase-Init using ConfigDrive2
- optional TPM 2.0

The build skips the upstream desktop gaming, HAGS, generic TCP, and Fast Startup tuning profile because those settings are inappropriate or unnecessary for a general PVE guest.

## Pinned guest dependencies

Dependency versions and checksums are stored in [`config/pve-dependencies.json`](config/pve-dependencies.json):

- VirtIO Windows drivers `0.1.285-1`
- Cloudbase-Init `1.1.8`
- an exact Chocolatey QEMU package version for `qemu-img`

Only these W11 x64 VirtIO driver families are injected:

```text
vioscsi, viostor, NetKVM, Balloon, vioserial, pvpanic, viorng
```

QEMU Guest Agent and Cloudbase-Init are staged inside the offline image and installed by `SetupComplete.cmd`. No fixed password is embedded. Cloudbase-Init obtains guest configuration from the PVE ConfigDrive2 data source.

## GitHub Actions build

The repository keeps three visible workflows, matching the original build organization:

- `Build Tiny11 PVE Candidate`
- `Build Tiny11 Core PVE Candidate`
- `Build Nano11 PVE Candidate`

To build:

1. Open the repository’s **Actions** page.
2. Select the required variant.
3. Choose **Run workflow**.
4. Supply a valid official Windows 11 x64 ISO URL.
5. Select the Windows image index and virtual disk size.
6. Download the resulting Actions Artifact.

The three public workflows call `.github/workflows/pve-candidate-reusable.yml`. PVE candidates are uploaded only as GitHub Actions Artifacts with seven-day retention. This branch does not publish them to GitHub Releases or SourceForge.

Each artifact contains:

```text
*-candidate.qcow2
*-candidate.qcow2.sha256
*-candidate.qcow2.manifest.json
```

The generated manifest explicitly records:

```json
{
  "target": "Proxmox VE 8.4/9.x",
  "validation_level": "static-only",
  "runtime_validated": false,
  "hardware_validated": false
}
```

## Local Windows build

Local construction requires an elevated Windows 10/11 or Windows Server environment with PowerShell 5.1+, DISM, sufficient free disk space, and `qemu-img.exe`.

Mount an official Windows 11 x64 ISO, download the pinned VirtIO ISO and Cloudbase-Init MSI from the URLs in the dependency manifest, then invoke one of the three scripts:

```powershell
$common = @{
    ISO = 'E'
    INDEX = 6
    VirtioISOPath = 'C:\build\virtio-win.iso'
    CloudbaseInitMSIPath = 'C:\build\CloudbaseInitSetup.msi'
    QemuImgPath = 'C:\Program Files\qemu\qemu-img.exe'
    DiskSizeGB = 32
}

# Standard
.\scripts\tiny11maker-headless.ps1 @common

# Core
.\scripts\tiny11coremaker-headless.ps1 @common

# Nano
.\scripts\nano11builder-headless.ps1 @common
```

Optional parameters retained from the original builders include `-SCRATCH`, `-SkipCleanup`, Core’s `-ENABLE_DOTNET35`, and Core/Nano’s `-PreserveWinRE`.

## Import into Proxmox VE

Copy the QCOW2, checksum, and import helper to a PVE node, then run:

```bash
sudo ./scripts/import-pve-template.sh \
  120 \
  ./nano11-pve-candidate.qcow2 \
  local-lvm \
  vmbr0 \
  nano11
```

The helper verifies SHA-256, creates the Q35/OVMF VM, imports the disk, attaches a ConfigDrive2 cloud-init disk, and enables the recommended VirtIO and QEMU Agent settings. TPM remains optional and is not added automatically.

Before using a candidate as a template, complete the real-node checklist in [`docs/PVE.md`](docs/PVE.md), including first boot, Secure Boot, storage/network devices, QEMU Agent, Cloudbase-Init, clone, shutdown, snapshot, discard, ballooning, and disk expansion tests.

## N5105 graphics scope

This branch does not integrate N5105/Jasper Lake GPU sharing, SR-IOV, GVT-g, PCI passthrough, or Intel GPU guest drivers. The candidate uses the ordinary PVE virtual display.

That boundary is intentional: a successful CI build cannot validate GPU sharing on hardware that the runner does not possess. Any future graphics experiment must be implemented and validated separately on the actual host.

## Repository layout

```text
.github/workflows/
  build-tiny11.yml
  build-tiny11-core.yml
  build-nano11.yml
  pve-candidate-reusable.yml
config/
  pve-dependencies.json
docs/
  PVE.md
scripts/
  modules/PveTemplateBuilder/
  import-pve-template.sh
  tiny11maker-headless.ps1
  tiny11coremaker-headless.ps1
  nano11builder-headless.ps1
tests/
  pve-static.Tests.ps1
```

## Validation boundary

CI and the shared builder check dependency hashes, required driver paths, QCOW2 format, virtual size, `qemu-img check`, artifact checksum, and manifest fields.

They do not prove:

- that Windows reaches the desktop on a specific PVE release
- that first-boot MSI installation succeeds for every Windows build
- that QEMU Agent and Cloudbase-Init operate correctly on the target network/storage setup
- that the candidate is stable on an Intel N5105 host
- that Core or Nano retains every feature required by a particular workload

Treat the output as a candidate until the runtime checklist has passed on the intended PVE host.

## Attribution and license

This project is based on the original [tiny11builder by ntdevlabs](https://github.com/ntdevlabs/tiny11builder). The headless automation was developed by [kelexine](https://github.com/kelexine). PVE candidate changes preserve the three original variant entry points and are released under the repository’s [MIT License](LICENSE).

You must supply a properly licensed Windows source image and comply with Microsoft’s licensing terms. No Windows binaries are stored in this repository.
