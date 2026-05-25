param(
    [Parameter(Mandatory = $true)] [string] $Target,
    [Parameter(Mandatory = $true)] [string] $Source,
    [Parameter(Mandatory = $true)] [string] $Keyword,
    [string] $File = '',
    [int] $MaxMatches = 200
)
. "$PSScriptRoot\common.ps1"
Assert-MaxMatches -MaxMatches $MaxMatches
$targetConfig = Get-TargetConfig -Target $Target
$sourceConfig = Get-SourceConfig -TargetConfig $targetConfig -Source $Source
$remote = New-SourceReadCommand -SourceConfig $sourceConfig -Action 'search' -File $File -Keyword $Keyword -MaxMatches $MaxMatches
$result = Invoke-SourceRead -SourceConfig $sourceConfig -RemoteCommand $remote -Audit @{ action = 'search-logs'; file = $File; keyword = $Keyword; max_matches = $MaxMatches }
$matches = if ([string]::IsNullOrWhiteSpace($result.output)) { @() } else { @($result.output -split "`r?`n") }
$payload = @{ ok = ($result.exit_code -eq 0); target = $Target; source = $Source; source_type = $sourceConfig.type; account = $sourceConfig.account.name; dir = $sourceConfig.dir; file = $File; keyword = $Keyword; max_matches = $MaxMatches; exit_code = $result.exit_code; match_count = $matches.Count; matches = $matches; stdout = $result.output; error = if ($result.exit_code -eq 0) { $null } else { 'script_command_failed' } }
if ($sourceConfig.type -eq 'docker') { $payload.container = $sourceConfig.container }
Write-Json $payload
