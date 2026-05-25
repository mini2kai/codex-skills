param([Parameter(Mandatory = $true)] [string] $Target)
. "$PSScriptRoot\common.ps1"
$targetConfig = Get-TargetConfig -Target $Target
$sources = @()
foreach ($property in $targetConfig.sources.PSObject.Properties) {
    $entry = $property.Value
    $type = Get-StringOrDefault -Object $entry -Name 'type'
    $defaultAccount = Get-StringOrDefault -Object $targetConfig -Name 'defaultAccount'
    $account = Get-StringOrDefault -Object $entry -Name 'account' -Default $defaultAccount
    $source = @{
        name = $property.Name
        description = Get-StringOrDefault -Object $entry -Name 'description'
        type = $type
        account = $account
    }
    if ($type -eq 'host_dir') {
        $source.abs_dir = Get-StringOrDefault -Object $entry -Name 'absDir'
    } elseif ($type -eq 'docker') {
        $source.container = Get-StringOrDefault -Object $entry -Name 'container'
        $source.log_dir = Get-StringOrDefault -Object $entry -Name 'logDir' -Default 'logs'
    }
    $sources += $source
}
Write-Json @{ ok = $true; target = $Target; sources = [object[]]$sources }
