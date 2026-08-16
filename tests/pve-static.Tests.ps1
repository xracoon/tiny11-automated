$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'scripts/modules/PveTemplateBuilder/PveTemplateBuilder.psm1'
$moduleText = Get-Content $module -Raw
$deps = Get-Content (Join-Path $root 'config/pve-dependencies.json') -Raw | ConvertFrom-Json

if ($deps.virtio.version -ne '0.1.285-1') { throw 'VirtIO version is not pinned as expected.' }
if ($deps.cloudbase_init.version -ne '1.1.8') { throw 'Cloudbase-Init version is not pinned as expected.' }
if ($deps.qemu.chocolatey_version -notmatch '^\d+\.\d+\.\d+$') { throw 'QEMU package version must be exact.' }

@('vioscsi','viostor','NetKVM','Balloon','vioserial','pvpanic','viorng') | ForEach-Object {
    if ($_ -notin $deps.virtio.drivers) { throw "Missing required VirtIO driver: $_" }
}
@('static-only','runtime_validated = $false','hardware_validated = $false','ConfigDrive2','q35') | ForEach-Object {
    if (-not $moduleText.Contains($_)) { throw "Module is missing required marker: $_" }
}

$builders = @('tiny11maker-headless.ps1','tiny11coremaker-headless.ps1','nano11builder-headless.ps1')
foreach ($builder in $builders) {
    $text = Get-Content (Join-Path $root "scripts/$builder") -Raw
    if (-not $text.Contains('New-PveCandidateTemplate')) { throw "$builder is not connected to the shared PVE module." }
    if ($text -notmatch '-candidate\.qcow2') { throw "$builder does not produce a candidate QCOW2 name." }
}

Write-Output 'PVE static contract checks passed.'
