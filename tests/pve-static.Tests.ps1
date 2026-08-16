$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Join-Path $root 'scripts/modules/PveTemplateBuilder/PveTemplateBuilder.psm1'
$moduleText = Get-Content $module -Raw
$workflowText = Get-Content (Join-Path $root '.github/workflows/pve-candidate-reusable.yml') -Raw
$deps = Get-Content (Join-Path $root 'config/pve-dependencies.json') -Raw | ConvertFrom-Json

if ($deps.virtio.version -ne '0.1.285-1') { throw 'VirtIO version is not pinned as expected.' }
if ($deps.virtio.url -notmatch '/virtio-win-0\.1\.285\.iso$') { throw 'VirtIO URL must use the versioned ISO filename.' }
if ($deps.virtio.hash -ne '4f13070cc9241fa342deab4ebfac360565030580ff77b6e5f1951a64627621e5da4abfd30e1e46ca8bae2bb7dd4ff98141aff424142c9629a5876a61283962e5') { throw 'VirtIO ISO SHA-512 is not pinned as expected.' }
if ($deps.cloudbase_init.version -ne '1.1.8') { throw 'Cloudbase-Init version is not pinned as expected.' }
if ($deps.qemu.chocolatey_version -notmatch '^\d+\.\d+\.\d+$') { throw 'QEMU package version must be exact.' }

@('vioscsi','viostor','NetKVM','Balloon','vioserial','pvpanic','viorng') | ForEach-Object {
    if ($_ -notin $deps.virtio.drivers) { throw "Missing required VirtIO driver: $_" }
}
@('static-only','runtime_validated = $false','hardware_validated = $false','ConfigDrive2','q35') | ForEach-Object {
    if (-not $moduleText.Contains($_)) { throw "Module is missing required marker: $_" }
}
if ($moduleText.Contains("'/Compact'")) { throw 'PVE image application must not require unsupported DISM CompactOS mode.' }
if (-not $moduleText.Contains("'0x{0:X8}'")) { throw 'Native command failures must include a hexadecimal Windows error code.' }
@('failure-diagnostics','intermediate-wim','Dependency checksum mismatch') | ForEach-Object {
    if (-not $workflowText.Contains($_)) { throw "Reusable workflow is missing diagnostic marker: $_" }
}

$builders = @('tiny11maker-headless.ps1','tiny11coremaker-headless.ps1','nano11builder-headless.ps1')
foreach ($builder in $builders) {
    $text = Get-Content (Join-Path $root "scripts/$builder") -Raw
    if (-not $text.Contains('New-PveCandidateTemplate')) { throw "$builder is not connected to the shared PVE module." }
    if ($text -notmatch '-candidate\.qcow2') { throw "$builder does not produce a candidate QCOW2 name." }
    if (-not $text.Contains('EditionId = "Professional"')) { throw "$builder does not resolve localized Pro editions by EditionId." }
    if (-not $text.Contains('Refusing to build the wrong edition')) { throw "$builder can silently build the wrong localized edition." }
}

Write-Output 'PVE static contract checks passed.'
