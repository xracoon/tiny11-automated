$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'scripts/modules/PveTemplateBuilder/PveTemplateBuilder.psm1'
$moduleText = Get-Content $module -Raw
$nanoPath = Join-Path $root 'scripts/nano11builder-headless.ps1'
$nanoText = Get-Content $nanoPath -Raw
$workflowPath = Join-Path $root '.github/workflows/build-nano11.yml'
$workflowText = Get-Content $workflowPath -Raw
$deps = Get-Content (Join-Path $root 'config/pve-dependencies.json') -Raw | ConvertFrom-Json

if ($deps.virtio.version -ne '0.1.285-1') { throw 'VirtIO version is not pinned as expected.' }
if ($deps.virtio.url -notmatch '/virtio-win-0\.1\.285\.iso$') { throw 'VirtIO URL must use the versioned ISO filename.' }
if ($deps.virtio.hash -ne '4f13070cc9241fa342deab4ebfac360565030580ff77b6e5f1951a64627621e5da4abfd30e1e46ca8bae2bb7dd4ff98141aff424142c9629a5876a61283962e5') { throw 'VirtIO ISO SHA-512 is not pinned as expected.' }
if ($deps.cloudbase_init.version -ne '1.1.8') { throw 'Cloudbase-Init version is not pinned as expected.' }
if ($deps.qemu.chocolatey_version -notmatch '^\d+\.\d+\.\d+$') { throw 'QEMU package version must be exact.' }

@('vioscsi','viostor','NetKVM','Balloon','vioserial','pvpanic','viorng') | ForEach-Object {
    if ($_ -notin $deps.virtio.drivers) { throw "Missing required VirtIO driver: $_" }
}
@('static-only','runtime_validated = $false','hardware_validated = $false','ConfigDrive2','q35',"language = `$Language",'microsoft-pinyin','Windows\Panther','SkipMachineOOBE','SkipUserOOBE',"default_user = 'Administrator'","default_password = 'blank'",'auto_logon = $false') | ForEach-Object {
    if (-not $moduleText.Contains($_)) { throw "Module is missing required marker: $_" }
}
if ($moduleText.Contains("'/Compact'")) { throw 'PVE image application must not require unsupported DISM CompactOS mode.' }
if (-not $moduleText.Contains("'0x{0:X8}'")) { throw 'Native command failures must include a hexadecimal Windows error code.' }
if ($moduleText.Contains('<AutoLogon>')) { throw 'PVE candidates must stop at the login screen instead of enabling AutoLogon.' }

@('Set-ZhCnInternationalSettings','Assert-ZhCnSupport','Language.Basic~~~zh-CN~0.0.1.0','InputMethod\CHS','msyh*.ttc','simsun*.ttc','nano11-zh-cn-pve-candidate.qcow2') | ForEach-Object {
    if (-not $nanoText.Contains($_)) { throw "Nano builder is missing zh-CN contract marker: $_" }
}
@('EditionId = "Professional"','Refusing to build the wrong edition') | ForEach-Object {
    if (-not $nanoText.Contains($_)) { throw "Nano builder is missing edition-resolution marker: $_" }
}
if ($nanoText.Contains('"*IME-zh-cn*"')) { throw 'Nano builder still removes the zh-CN IME package.' }
if ($workflowText.Contains('pve-candidate-reusable.yml')) { throw 'Nano workflow must be self-contained.' }
if (-not $workflowText.Contains('nano11-zh-cn-pve-candidate.qcow2')) { throw 'Nano workflow does not upload the zh-CN candidate.' }
if (-not $workflowText.Contains('nano11-zh-cn-failure-diagnostics')) { throw 'Nano workflow does not upload failure diagnostics.' }
if (-not $workflowText.Contains('nano11-zh-cn-intermediate-wim')) { throw 'Nano workflow does not upload retained intermediate WIM files.' }
if ($workflowText -notmatch '(?s)skip_cleanup:.+?default: false') { throw 'Intermediate WIM retention must be unchecked by default.' }
$importText = Get-Content (Join-Path $root 'scripts/import-pve-template.sh') -Raw
@('--cipassword','--ipconfig0 ip=dhcp','Administrator with a blank password') | ForEach-Object {
    if (-not $importText.Contains($_)) { throw "PVE import helper is missing provisioning marker: $_" }
}
foreach ($retired in @('build-tiny11.yml','build-tiny11-core.yml','pve-candidate-reusable.yml','version-matrix-builder.yml','update-stats.yml')) {
    if (Test-Path (Join-Path $root ".github/workflows/$retired")) { throw "Retired workflow still exists: $retired" }
}

Write-Output 'Nano11 zh-CN PVE static contract checks passed.'
