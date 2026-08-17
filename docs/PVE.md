# Proxmox VE candidate images

This branch keeps the original Standard, Core, and Nano build entry points, but their final product is a compressed `*-candidate.qcow2` instead of an installer ISO. Shared PVE work lives in `PveTemplateBuilder`; Nano is not the baseline and receives VirtIO drivers only after its DriverStore pruning.

## What the build does

- Creates a 32 GiB expandable GPT disk by default: 260 MiB EFI, 16 MiB MSR, and an NTFS Windows partition.
- Applies the single-index customized WIM with standard DISM image application, creates UEFI boot files, then converts VHDX to compressed QCOW2. Final compression is handled by `qemu-img` without relying on host CompactOS/WOF support.
- Injects only W11 x64 `vioscsi`, `viostor`, `NetKVM`, `Balloon`, `vioserial`, `pvpanic`, and `viorng` drivers from the pinned VirtIO ISO.
- Stages the pinned QEMU Guest Agent and Cloudbase-Init installers for `SetupComplete.cmd`. Cloudbase-Init uses ConfigDrive2 and accepts an optional password supplied by PVE cloud-init; the image contains no fixed non-empty password.
- Writes a PVE-specific `Windows\Panther\unattend.xml` because direct WIM deployment does not consume the installer ISO answer file. It skips OOBE, enables `Administrator` with a blank default password, disables AutoLogon, and requests a Windows-generated unique computer name.
- Disables Fast Startup and omits the upstream desktop/gaming/HAGS/TCP tuning profile.
- Runs `qemu-img check`, validates format and virtual size, and emits SHA-256 plus a JSON manifest.

The manifest deliberately says `static-only`, `runtime_validated: false`, and `hardware_validated: false`. GitHub-hosted runners cannot prove boot behavior on your PVE node or N5105 hardware.

## Recommended VM profile

Use Q35, OVMF with pre-enrolled Secure Boot keys, VirtIO SCSI single, IO thread, discard, VirtIO NIC, ballooning, QEMU Agent, and ConfigDrive2. TPM 2.0 is optional. The included import helper applies this profile:

```bash
sudo ./scripts/import-pve-template.sh 120 ./nano11-pve-candidate.qcow2 local-lvm vmbr0 nano11
```

Production example with an explicit password:

```bash
sudo ./scripts/import-pve-template.sh \
  120 ./nano11-pve-candidate.qcow2 local-lvm vmbr0 nano11 \
  --cipassword 'replace-with-a-strong-password' --template
```

The default login is `Administrator` with a blank password and is intended only for isolated PVE console testing. The helper configures ConfigDrive2 and DHCP by default. PVE does not reliably apply Windows `ciuser`, so `Administrator` is fixed by the Cloudbase-Init configuration; `--cipassword` changes only its password. Do not combine `--cipassword` with `--no-cloudinit`.

The command-line password can be stored in shell history or briefly visible in process arguments. Use a controlled terminal and follow the local history-cleanup policy.

## Expected first boot

The normal result is the login screen in the source image's language, not an automatic desktop login. Language selection, network setup, update checks, computer-name selection, account creation, and privacy OOBE pages should not appear. Windows generates the guest computer name independently from the PVE VM name. Cloudbase-Init may reboot once while applying ConfigDrive2 data.

If OOBE still appears, inspect `%WINDIR%\Panther\UnattendGC\setupact.log` and `setuperr.log`. For guest integration failures, inspect `%WINDIR%\Temp\pve-firstboot.log`, `qemu-ga-install.log`, and `cloudbase-init-install.log`.

The helper verifies the checksum before creating the VM and resolves the volume name reported by `qm importdisk` instead of assuming a disk number.

## Required runtime validation on the actual PVE node

1. Boot with Secure Boot enabled and confirm Windows skips OOBE, reaches the login screen, and does not enter repair mode.
2. Confirm Device Manager has no missing boot-storage or network devices.
3. Confirm `QEMU-GA` and `cloudbase-init` exist and run; inspect `%WINDIR%\Temp\pve-firstboot.log` and MSI logs on failure.
4. Confirm DHCP and an optional `--cipassword` arrive through ConfigDrive2. Verify that two clones receive distinct Windows-generated computer names.
5. Verify PVE reports the guest IP and agent state, then test clean shutdown, snapshot restore, clone, discard/TRIM, ballooning, and disk expansion.
6. Repeat the checklist for every Windows build and every Standard/Core/Nano variant you intend to use.

## N5105 graphics boundary

This branch does not configure GPU sharing, SR-IOV, mediated devices/GVT-g, PCI passthrough, or Intel GPU guest drivers. Display remains the ordinary PVE virtual display. Any future GPU experiment must be a separately documented host/guest test and must not be advertised as supported based only on a successful image build.
