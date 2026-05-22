. "$PSScriptRoot\common.ps1"
$config = Get-LocalConfig
$targets = @()
foreach ($property in $config.targets.PSObject.Properties) {
    $item = $property.Value
    $containers = @()
    if ($item.PSObject.Properties.Name.Contains('containers') -and $null -ne $item.containers) {
        if ($item.containers -is [System.Array]) {
            $containers = @($item.containers)
        } else {
            $containers = @($item.containers.PSObject.Properties.Name)
        }
    }
    $targets += @{
        name = $property.Name
        description = if ($item.PSObject.Properties.Name.Contains('description')) { [string]$item.description } else { '' }
        containers = $containers
    }
}
Write-Json @{ ok = $true; targets = $targets }
