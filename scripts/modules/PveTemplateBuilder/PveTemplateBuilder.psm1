Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-NativeChecked {
    param([string]$FilePath, [string[]]$ArgumentList)
    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        $unsignedExitCode = [uint32]([int64]$LASTEXITCODE -band 0xffffffffL)
        $hexExitCode = '0x{0:X8}' -f $unsignedExitCode
        throw "$FilePath $($ArgumentList -join ' ') failed with exit code $LASTEXITCODE ($hexExitCode)"
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

function Set-PveUnattend {
    param([Parameter(Mandatory)][string]$MountPath)

    # PVE candidates are created by applying install.wim directly, so the ISO
    # root answer file is never consumed. Panther is the documented answer-file
    # location used while the applied image enters specialize/oobeSystem.
    $panther = Join-Path $MountPath 'Windows\Panther'
    New-Item -ItemType Directory -Path $panther -Force | Out-Null
    $unattend = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
  <settings pass="specialize">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <ComputerName>*</ComputerName>
      <RegisteredOwner>tiny11-automated</RegisteredOwner>
    </component>
    <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <RunSynchronous>
        <RunSynchronousCommand wcm:action="add">
          <Order>1</Order>
          <Description>Enable the built-in Administrator account</Description>
          <Path>cmd.exe /c net user Administrator /active:yes</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>2</Order>
          <Description>Use a blank local console password unless ConfigDrive sets one</Description>
          <Path>cmd.exe /c net user Administrator ""</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>3</Order>
          <Description>Skip OOBE and disable network/privacy prompts (25H2 ConX compatibility)</Description>
          <Path>cmd.exe /c reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE" /v SkipMachineOOBE /t REG_DWORD /d 1 /f &amp;&amp; reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE" /v SkipUserOOBE /t REG_DWORD /d 1 /f &amp;&amp; reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v BypassNRO /t REG_DWORD /d 1 /f &amp;&amp; reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v HideOnlineAccountScreens /t REG_DWORD /d 1 /f &amp;&amp; reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v PrivacyConsentStatus /t REG_DWORD /d 1 /f &amp;&amp; reg.exe add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v ProtectYourPC /t REG_DWORD /d 3 /f</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>4</Order>
          <Description>Remove ConX default account entries that force interactive OOBE</Description>
          <Path>cmd.exe /c reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v DefaultAccountAction /f 2&gt;nul &amp; reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v DefaultAccountSAMName /f 2&gt;nul &amp; reg.exe delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE" /v DefaultAccountSID /f 2&gt;nul</Path>
        </RunSynchronousCommand>
        <RunSynchronousCommand wcm:action="add">
          <Order>5</Order>
          <Description>Enable AutoLogon as Administrator for first boot</Description>
          <Path>cmd.exe /c reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d "1" /f &amp;&amp; reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d "Administrator" /f &amp;&amp; reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d "" /f &amp;&amp; reg.exe add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoLogonCount /t REG_DWORD /d 1 /f</Path>
        </RunSynchronousCommand>
      </RunSynchronous>
    </component>
  </settings>
  <settings pass="oobeSystem">
    <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
      <OOBE>
        <HideEULAPage>true</HideEULAPage>
        <HideLocalAccountScreen>true</HideLocalAccountScreen>
        <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
        <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
        <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
        <ProtectYourPC>3</ProtectYourPC>
      </OOBE>
      <UserAccounts>
        <AdministratorPassword>
          <Value></Value>
          <PlainText>true</PlainText>
        </AdministratorPassword>
      </UserAccounts>
      <AutoLogon>
        <Enabled>true</Enabled>
        <LogonCount>1</LogonCount>
        <Username>Administrator</Username>
        <Password>
          <Value></Value>
          <PlainText>true</PlainText>
        </Password>
      </AutoLogon>
    </component>
  </settings>
</unattend>
'@
    Set-Content -LiteralPath (Join-Path $panther 'unattend.xml') -Value $unattend -Encoding UTF8
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

    $blnSvr = Get-ChildItem -LiteralPath (Join-Path $VirtioRoot 'Balloon\w11\amd64') -Filter 'blnsvr.exe' -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $blnSvr) { throw 'blnsvr.exe was not found in the pinned VirtIO ISO.' }
    Copy-Item -LiteralPath $blnSvr.FullName -Destination (Join-Path $MountPath 'Windows\System32\blnsvr.exe') -Force

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

    Set-PveUnattend -MountPath $MountPath

    $setupComplete = @'
@echo off
setlocal
set "PVE_PAYLOAD=%WINDIR%\Setup\Scripts\Pve"
set "PVE_LOG=%WINDIR%\Temp\pve-firstboot.log"
echo [%DATE% %TIME%] Installing QEMU Guest Agent>>"%PVE_LOG%"
call :install_msi "%PVE_PAYLOAD%\qemu-ga-x86_64.msi" /l*v "%WINDIR%\Temp\qemu-ga-install.log"
if errorlevel 1 goto :failed
echo [%DATE% %TIME%] Installing Cloudbase-Init>>"%PVE_LOG%"
call :install_msi "%PVE_PAYLOAD%\CloudbaseInitSetup.msi" RUN_SERVICE_AS_LOCAL_SYSTEM=1 /l*v "%WINDIR%\Temp\cloudbase-init-install.log"
if errorlevel 1 goto :failed
copy /y "%PVE_PAYLOAD%\cloudbase-init.conf" "%ProgramFiles%\Cloudbase Solutions\Cloudbase-Init\conf\cloudbase-init.conf">>"%PVE_LOG%" 2>&1
sc config QEMU-GA start= auto>>"%PVE_LOG%" 2>&1
sc config cloudbase-init start= auto>>"%PVE_LOG%" 2>&1
sc start QEMU-GA>>"%PVE_LOG%" 2>&1
sc start cloudbase-init>>"%PVE_LOG%" 2>&1
sc query QEMU-GA>>"%PVE_LOG%" 2>&1
sc query cloudbase-init>>"%PVE_LOG%" 2>&1
if errorlevel 1 goto :failed
del /q "%PVE_PAYLOAD%\*.msi"
echo [%DATE% %TIME%] Registering XAML/AppX packages (KB5072911 fix)>>"%PVE_LOG%"
powershell.exe -ExecutionPolicy Bypass -Command "Add-AppxPackage -Register -Path 'C:\Windows\SystemApps\MicrosoftWindows.Client.CBS_cw5n1h2txyewy\appxmanifest.xml' -DisableDevelopmentMode" >>"%PVE_LOG%" 2>&1
powershell.exe -ExecutionPolicy Bypass -Command "Add-AppxPackage -Register -Path 'C:\Windows\SystemApps\Microsoft.UI.Xaml.CBS_8wekyb3d8bbwe\appxmanifest.xml' -DisableDevelopmentMode" >>"%PVE_LOG%" 2>&1
powershell.exe -ExecutionPolicy Bypass -Command "Add-AppxPackage -Register -Path 'C:\Windows\SystemApps\MicrosoftWindows.Client.Core_cw5n1h2txyewy\appxmanifest.xml' -DisableDevelopmentMode" >>"%PVE_LOG%" 2>&1
echo [%DATE% %TIME%] PVE guest integration staged successfully>>"%PVE_LOG%"
exit /b 0
:failed
echo [%DATE% %TIME%] PVE guest integration failed; payload retained for diagnosis>>"%PVE_LOG%"
exit /b 1
:install_msi
msiexec /i %1 /qn /norestart %2 %3 %4 %5 %6 %7 %8 %9
set "PVE_MSI_RC=%ERRORLEVEL%"
if "%PVE_MSI_RC%"=="0" exit /b 0
if "%PVE_MSI_RC%"=="1641" exit /b 0
if "%PVE_MSI_RC%"=="3010" exit /b 0
echo [%DATE% %TIME%] MSI installation failed with exit code %PVE_MSI_RC%>>"%PVE_LOG%"
exit /b 1
'@
    Set-Content -LiteralPath (Join-Path $MountPath 'Windows\Setup\Scripts\SetupComplete.cmd') -Value $setupComplete -Encoding Ascii

    $systemHive = Join-Path $MountPath 'Windows\System32\config\SYSTEM'
    Invoke-NativeChecked reg.exe @('load', 'HKLM\PVE_SYSTEM', $systemHive)
    try {
        Invoke-NativeChecked reg.exe @('add', 'HKLM\PVE_SYSTEM\ControlSet001\Control\Session Manager\Power', '/v', 'HiberbootEnabled', '/t', 'REG_DWORD', '/d', '0', '/f')

        $balloonSvc = 'HKLM\PVE_SYSTEM\ControlSet001\Services\BalloonService'
        Invoke-NativeChecked reg.exe @('add', $balloonSvc, '/v', 'Start',        '/t', 'REG_DWORD',     '/d', '2',  '/f')
        Invoke-NativeChecked reg.exe @('add', $balloonSvc, '/v', 'Type',         '/t', 'REG_DWORD',     '/d', '16', '/f')
        Invoke-NativeChecked reg.exe @('add', $balloonSvc, '/v', 'ErrorControl', '/t', 'REG_DWORD',     '/d', '1',  '/f')
        Invoke-NativeChecked reg.exe @('add', $balloonSvc, '/v', 'ImagePath',    '/t', 'REG_EXPAND_SZ', '/d', '%SystemRoot%\System32\blnsvr.exe', '/f')
        Invoke-NativeChecked reg.exe @('add', $balloonSvc, '/v', 'DisplayName',  '/t', 'REG_SZ',        '/d', 'Balloon Service', '/f')
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
        [ValidateSet('zh-CN')][string]$Language = 'zh-CN',
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
        # Do not use /Compact here. GitHub-hosted Windows runners can reject
        # CompactOS application to an attached dynamic VHDX with 0xC144013B
        # when their WOF driver does not support it. The final QCOW2 is compressed
        # independently by qemu-img, so /Compact is unnecessary for the artifact.
        Invoke-NativeChecked dism.exe @('/English', '/Apply-Image', "/ImageFile:$ImagePath", "/Index:$ImageIndex", "/ApplyDir:$windowsLetter`:\")
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
        variant = $Variant; language = $Language; target = 'Proxmox VE 8.4/9.x'; validation_level = 'static-only'
        runtime_validated = $false; hardware_validated = $false; disk_size_gib = $DiskSizeGB
        provisioning = [ordered]@{ oobe_skipped = $true; default_user = 'Administrator'; default_password = 'blank'; auto_logon = $false; hostname_source = 'windows-generated'; cloud_init_user = 'Administrator' }
        chinese_support = @('ui', 'microsoft-pinyin', 'basic-fonts', 'basic-language-features')
        firmware = 'OVMF (UEFI)'; machine = 'q35'; secure_boot_compatible = $true
        recommended = [ordered]@{ scsi_controller = 'VirtIO SCSI single'; iothread = $true; discard = $true; nic = 'VirtIO'; balloon = $true; qemu_agent = $true; cloud_init = 'ConfigDrive2'; tpm = 'optional' }
        gpu_sharing = [ordered]@{ integrated = $false; note = 'No N5105/Jasper Lake GPU sharing, SR-IOV, GVT-g, or Intel GPU driver integration.' }
        dependencies = [ordered]@{ virtio = $dependencies.virtio.version; cloudbase_init = $dependencies.cloudbase_init.version; qemu = $dependencies.qemu.chocolatey_version }
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath "$OutputPath.manifest.json" -Encoding UTF8
    Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue
    Get-Item -LiteralPath $OutputPath
}

Export-ModuleMember -Function New-PveCandidateTemplate
