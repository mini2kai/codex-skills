. "$PSScriptRoot\common.ps1"
$config = Get-LocalConfig
$targets = @()
foreach ($property in $config.targets.PSObject.Properties) {
    $item = $property.Value
    $hasAccounts = Has-Property -Object $item -Name 'accounts'
    $hasSources = Has-Property -Object $item -Name 'sources'
    $accounts = if ($hasAccounts -and $null -ne $item.accounts) { @($item.accounts.PSObject.Properties.Name) } else { @() }
    $sources = if ($hasSources -and $null -ne $item.sources) { @($item.sources.PSObject.Properties.Name) } else { @() }
    $targets += @{
        name = $property.Name
        description = if ($item.PSObject.Properties.Name.Contains('description')) { [string]$item.description } else { '' }
        default_account = if ($item.PSObject.Properties.Name.Contains('defaultAccount')) { [string]$item.defaultAccount } else { '' }
        accounts = [object[]]$accounts
        sources = [object[]]$sources
    }
}
Write-Json @{ ok = $true; targets = [object[]]$targets }
