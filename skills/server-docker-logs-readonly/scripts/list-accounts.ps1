param([Parameter(Mandatory = $true)] [string] $Target)
. "$PSScriptRoot\common.ps1"
$targetConfig = Get-TargetConfig -Target $Target
$accounts = @()
foreach ($property in $targetConfig.accounts.PSObject.Properties) {
    $entry = $property.Value
    $hasPermissionProperty = Has-Property -Object $entry -Name 'permissions'
    $hasPermissions = ($hasPermissionProperty -and $null -ne $entry.permissions)
    $hostDirAllowed = if ($hasPermissions) { Get-BoolOrDefault -Object $entry.permissions -Name 'hostDir' -Default $false } else { $false }
    $dockerAllowed = if ($hasPermissions) { Get-BoolOrDefault -Object $entry.permissions -Name 'docker' -Default $false } else { $false }
    $accounts += @{
        name = $property.Name
        description = Get-StringOrDefault -Object $entry -Name 'description'
        role = Get-StringOrDefault -Object $entry -Name 'role' -Default 'readonly'
        permissions = @{
            host_dir = $hostDirAllowed
            docker = $dockerAllowed
        }
    }
}
$defaultAccount = Get-StringOrDefault -Object $targetConfig -Name 'defaultAccount'
Write-Json @{ ok = $true; target = $Target; default_account = $defaultAccount; accounts = $accounts }
