param(
    [Parameter(Mandatory = $true)] [string] $Target,
    [Parameter(Mandatory = $true)] [string] $Source
)
. "$PSScriptRoot\common.ps1"
$targetConfig = Get-TargetConfig -Target $Target
$sourceConfig = Get-SourceConfig -TargetConfig $targetConfig -Source $Source
$remote = New-SourceReadCommand -SourceConfig $sourceConfig -Action 'list'
$result = Invoke-SourceRead -SourceConfig $sourceConfig -RemoteCommand $remote -Audit @{ action = 'list-log-files' }
$files = if ([string]::IsNullOrWhiteSpace($result.output)) { @() } else { @($result.output -split "`r?`n") }
$payload = @{ ok = ($result.exit_code -eq 0); target = $Target; source = $Source; source_type = $sourceConfig.type; account = $sourceConfig.account.name; dir = $sourceConfig.dir; exit_code = $result.exit_code; files = [object[]]$files; stdout = $result.output; error = if ($result.exit_code -eq 0) { $null } else { 'script_command_failed' } }
if ($sourceConfig.type -eq 'docker') { $payload.container = $sourceConfig.container }
Write-Json $payload
