@{
    RootModule = 'PveTemplateBuilder.psm1'
    ModuleVersion = '1.2.0'
    GUID = '2271e829-c190-47bb-9912-d494c467d375'
    Author = 'tiny11-automated contributors'
    Description = 'Builds unattended, statically validated Proxmox VE candidate QCOW2 images.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('New-PveCandidateTemplate')
}
