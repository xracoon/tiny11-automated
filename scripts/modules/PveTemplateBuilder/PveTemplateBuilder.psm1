Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NativeChecked {
    param([string]$FilePath, [string[]]$ArgumentList)
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "$FilePath failed with exit code $LASTEXITCODE"
    }
}

function Assert-FileHash {
    param([string]$Path, [pscustomobject]$Definition)
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm $Definition.hash_algorithm).Hash
    if ($actual -ine $Definition.hash) {
        throw "Checksum mismatch for $Path. Expected $($Definition.hash), got $actual."
    }
}

function Get-FreeDriveLetters {
    param([int]$Count)
    $used = (Get-PSDrive -PSProvider FileSystem).Name
    $letters = [char[]](67..89) | ForEach-Object { $_.ToString() } | Where-Object { $_ -notin $used }
    if ($letters.Count -lt $Count) { throw 'Not enough free drive letters to construct the template disk.' }
    return @($letters | Select-Object -First $Count)
}

function Add-PveOfflinePayload {
    param(
        [string]$MountPath,
        [string]$VirtioRoot,
        [string]$CloudbaseInitMsiPath,
        [string[]]$Drivers
    )
    foreach ($driver in $Drivers) {
        $driverPath = Join-Path $VirtioRoot "$driver\w11\amd64"
        if (-not (Test-Path -LiteralPath $driverPath)) { throw "Required W11 amd64 VirtIO driver is missing: $driverPath" }
        Add-WindowsDriver -Path $MountPath -Driver $driverPath -Recurse -ForceUnsigned:$false | Out-Null
    }

    $guestAgent = Get-ChildItem -LiteralPath (Join-Path $VirtioRoot 'guest-agent') -Filter 'qemu-ga-x86_64.msi' -File -Recurse | Select-Object -First 1
    if (-not $guestAgent) { throw 'qemu-ga-x86_64.msi was not found in the pinned VirtIO ISO.' }

    $payload = Join-Path $MountPath 'Windows\Setup\Scripts\Pve'
    New-Item -ItemType Directory -Path $payload -Force | Out-Null
    Copy-Item -LiteralPath $guestAgent.FullName -Destination (Join-Path $payload 'qemu-ga-x86_64.msi') -Force
    Copy-Item -LiteralPath $CloudbaseInitMsiPath -Destination (Join-Path $payload 'CloudbaseInitSetup.msi') -Force

    $cloudbaseConf = @'
[DEFAULT]
username=Administrator
groups=Administrators
inject_user_password=true
first_logon_behaviour=no
rename_admin_user=false
allow_reboot=true
metadata_services=cloudbaseinit.metadata.services.configdrive.ConfigDriveService
plugins=cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,cloudbaseinit.plugins.windows.createuser.CreateUserPlugin,cloudbaseinit.plugins.common.setuserpassword.SetUserPasswordPlugin,cloudbaseinit.plugins.windows.networkconfig.NetworkConfigPlugin,cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin
serial_port=COM1
'@
    Set-Content -LiteralPath (Join-Path $payload 'cloudbase-init.conf') -Value $cloudbaseConf -Encoding Ascii

    $setupComplete = @'
@echo off
setlocal
set "PVE_PAYLOAD=%WINDIR%\Setup\Scripts\Pve"
set "PVE_LOG=%WINDIR%\Temp\pve-firstboot.log"
echo [%DATE% %TIME%] Installing QEMU Guest Agent>>"%PVE_LOG%"
msiexec /i "%PVE_PAYLOAD%\qemu-ga-x86_64.msi" /qn /norestart /l*v "%WINDIR%\Temp\qemu-ga-install.log"
if errorlevel 1 goto :failed
echo [%DATE% %TIME%] Installing Cloudbase-Init>>"%PVE_LOG%"
msiexec /i "%PVE_PAYLOAD%\CloudbaseInitSetup.msi" /qn /norestart RUN_SERVICE_AS_LOCAL_SYSTEM=1 /l*v "%WINDIR%\Temp\cloudbase-init-install.log"
if errorlevel 1 goto :failed
copy /y "%PVE_PAYLOAD%\cloudbase-init.conf" "%ProgramFiles%\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf">>"%PVE_LOG%" 2>&1
sc config QEMU-GA start= auto>>"%PVE_LOG%" 2>&1
sc config cloudbase-init start= auto>>"%PVE_LOG%" 2>&1
sc query QEMU-GA>>"%PVE_LOG%" 2>&1
sc query cloudbase-init>>"%PVE_LOG%" 2>&1
if errorlevel 1 goto :failed
del /q "%PVE_PAYLOAD%\*.msi"
echo [%DATE% %TIME%] PVE guest integration staged successfully>>"%PVE_LOG%"
exit /b 0
:failed
echo [%DATE% %TIME%] PVE guest integration failed; payload retained for diagnosis>>"%PVE_LOG%"
exit /b 1
'@
    Set-Content -LiteralPath (Join-Path $MountPath 'Windows\Setup\Scripts\SetupComplete.cmd') -Value $setupComplete -Encoding Ascii

    $systemHive = Join-Path $MountPath 'Windows\System32\config\SYSTEM'
    Invoke-NativeChecked reg.exe @('load', 'HKLM\PVE_SYSTEM', $systemHive)
    try {
        Invoke-NativeChecked reg.exe @('add', 'HKLM\PVE_SYSTEM\ControlSet001\Control\Session Manager\Power', '/v', 'HiberbootEnabled', '/t', 'REG_DWORD', '/d', '0', '/f')
    } finally {
        Invoke-NativeChecked reg.exe @('unload', 'HKLM\PVE_SYSTEM')
    }
}

function New-PveCandidateTemplate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ImagePath,
        [Parameter(Mandatory)][ValidateSet('standard','core','nano')][string]$Variant,
        [Parameter(Mandatory)][string]$OutputPath,
        [Parameter(Mandatory)][string]$VirtioIsoPath,
        [Parameter(Mandatory)][string]$CloudbaseInitMsiPath,
        [Parameter(Mandatory)][string]$DependencyManifestPath,
        [Parameter(Mandatory)][string]$QemuImgPath,
        [ValidateRange(16, 2048)][int]$DiskSizeGB = 32,
        [int]$ImageIndex = 1
    )
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Administrator privileges are required.' }
    foreach ($required in @($ImagePath, $VirtioIsoPath, $CloudbaseInitMsiPath, $DependencyManifestPath, $QemuImgPath)) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Required path not found: $required" }
    }

    $dependencies = Get-Content -LiteralPath $DependencyManifestPath -Raw | ConvertFrom-Json
    Assert-FileHash $VirtioIsoPath $dependencies.virtio
    Assert-FileHash $CloudbaseInitMsiPath $dependencies.cloudbase_init

    $workRoot = Join-Path ([IO.Path]::GetTempPath()) ("tiny11-pve-" + [guid]::NewGuid().ToString('N'))
    $mountPath = Join-Path $workRoot 'wim'
    $vhdxPath = Join-Path $workRoot "$Variant.vhdx"
    New-Item -ItemType Directory -Path $mountPath -Force | Out-Null
    $virtioImage = $null
    $mountedWim = $false
    $mountedVhd = $false
    try {
        $virtioImage = Mount-DiskImage -ImagePath $VirtioIsoPath -PassThru
        $virtioVolume = $virtioImage | Get-Volume | Where-Object DriveLetter | Select-Object -First 1
        if (-not $virtioVolume) { throw 'The VirtIO ISO did not expose a drive letter.' }

        Mount-WindowsImage -ImagePath $ImagePath -Index $ImageIndex -Path $mountPath | Out-Null
        $mountedWim = $true
        Add-PveOfflinePayload -MountPath $mountPath -VirtioRoot "$($virtioVolume.DriveLetter):\" -CloudbaseInitMsiPath $CloudbaseInitMsiPath -Drivers $dependencies.virtio.drivers
        Dismount-WindowsImage -Path $mountPath -Save | Out-Null
        $mountedWim = $false

        $letters = Get-FreeDriveLetters 2
        $efiLetter = $letters[0]
        $windowsLetter = $letters[1]
        $diskpartScript = Join-Path $workRoot 'diskpart.txt'
        @(
            "create vdisk file=`"$vhdxPath`" maximum=$($DiskSizeGB * 1024) type=expandable",
            "select vdisk file=`"$vhdxPath`"", 'attach vdisk', 'convert gpt',
            'create partition efi size=260', 'format quick fs=fat32 label="EFI"', "assign letter=$efiLetter",
            'create partition msr size=16', 'create partition primary', 'format quick fs=ntfs label="Windows"', "assign letter=$windowsLetter"
        ) | Set-Content -LiteralPath $diskpartScript -Encoding Ascii
        @("select vdisk file=`"$vhdxPath`"", 'detach vdisk') | Set-Content -LiteralPath (Join-Path $workRoot 'detach.txt') -Encoding Ascii
        Invoke-NativeChecked diskpart.exe @('/s', $diskpartScript)
        $mountedVhd = $true
        Invoke-NativeChecked dism.exe @('/English', '/Apply-Image', "/ImageFile:$ImagePath", "/Index:$ImageIndex", "/ApplyDir:$windowsLetter`:\", '/Compact')
        Invoke-NativeChecked bcdboot.exe @("$windowsLetter`:\Windows", '/s', "$efiLetter`:", '/f', 'UEFI')
        Invoke-NativeChecked diskpart.exe @('/s', (Join-Path $workRoot 'detach.txt'))
        $mountedVhd = $false
    } finally {
        if ($mountedWim) { Dismount-WindowsImage -Path $mountPath -Discard -ErrorAction SilentlyContinue | Out-Null }
        if ($virtioImage) { Dismount-DiskImage -ImagePath $VirtioIsoPath -ErrorAction SilentlyContinue }
        if ($mountedVhd) {
            "select vdisk file=`"$vhdxPath`"`ndetach vdisk" | Set-Content -LiteralPath (Join-Path $workRoot 'emergency-detach.txt') -Encoding Ascii
            & diskpart.exe /s (Join-Path $workRoot 'emergency-detach.txt') | Out-Null
        }
    }

    if (Test-Path "$windowsLetter`:\") { throw 'VHDX remained attached after construction.' }
    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory) { New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null }
    Invoke-NativeChecked $QemuImgPath @('convert', '-p', '-f', 'vhdx', '-O', 'qcow2', '-c', $vhdxPath, $OutputPath)
    Invoke-NativeChecked $QemuImgPath @('check', '-f', 'qcow2', $OutputPath)
    $infoJson = & $QemuImgPath info '--output=json' $OutputPath
    if ($LASTEXITCODE -ne 0) { throw 'qemu-img info failed.' }
    $info = $infoJson | ConvertFrom-Json
    if ($info.format -ne 'qcow2' -or [int64]$info.'virtual-size' -ne ($DiskSizeGB * 1GB)) { throw 'qemu-img reported an unexpected format or virtual size.' }

    $sha256 = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    "$sha256  $([IO.Path]::GetFileName($OutputPath))" | Set-Content -LiteralPath "$OutputPath.sha256" -Encoding Ascii
    [ordered]@{
        schema_version = 1; artifact = [IO.Path]::GetFileName($OutputPath); sha256 = $sha256
        variant = $Variant; target = 'Proxmox VE 8.4/9.x'; validation_level = 'static-only'
        runtime_validated = $false; hardware_validated = $false; disk_size_gib = $DiskSizeGB
        firmware = 'OVMF (UEFI)'; machine = 'q35'; secure_boot_compatible = $true
        recommended = [ordered]@{ scsi_controller = 'VirtIO SCSI single'; iothread = $true; discard = $true; nic = 'VirtIO'; balloon = $true; qemu_agent = $true; cloud_init = 'ConfigDrive2'; tpm = 'optional' }
        gpu_sharing = [ordered]@{ integrated = $false; note = 'No N5105/Jasper Lake GPU sharing, SR-IOV, GVT-g, or Intel GPU driver integration.' }
        dependencies = [ordered]@{ virtio = $dependencies.virtio.version; cloudbase_init = $dependencies.cloudbase_init.version; qemu = $dependencies.qemu.chocolatey_version }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$OutputPath.manifest.json" -Encoding UTF8
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    Get-Item -LiteralPath $OutputPath
}

Export-ModuleMember -Function New-PveCandidateTemplate
