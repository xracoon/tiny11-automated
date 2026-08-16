@{
    RootModule = 'PveTemplateBuilder.psm1'
    ModuleVersion = '1.1.0'
    GUID = '2271e829-c190-47bb-9912-d494c467d375'
    Author = 'tiny11-automated contributors'
    Description = 'Builds statically validated zh-CN Nano11 candidate QCOW2 images for Proxmox VE.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('New-PveCandidateTemplate')
}
