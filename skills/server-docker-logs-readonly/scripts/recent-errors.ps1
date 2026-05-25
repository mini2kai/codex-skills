param(
    [Parameter(Mandatory = $true)] [string] $Target,
    [Parameter(Mandatory = $true)] [string] $Source,
    [string] $File = '',
    [int] $MaxMatches = 200
)
. "$PSScriptRoot\common.ps1"
Assert-MaxMatches -MaxMatches $MaxMatches
$targetConfig = Get-TargetConfig -Target $Target
$sourceConfig = Get-SourceConfig -TargetConfig $targetConfig -Source $Source
$remote = New-SourceReadCommand -SourceConfig $sourceConfig -Action 'recent-errors' -File $File -MaxMatches $MaxMatches
$result = Invoke-SourceRead -SourceConfig $sourceConfig -RemoteCommand $remote -Audit @{ action = 'recent-errors'; file = $File; max_matches = $MaxMatches }
$findings = if ([string]::IsNullOrWhiteSpace($result.output)) { @() } else { @($result.output -split "`r?`n") }
$payload = @{ ok = ($result.exit_code -eq 0); target = $Target; source = $Source; source_type = $sourceConfig.type; account = $sourceConfig.account.name; dir = $sourceConfig.dir; file = $File; max_matches = $MaxMatches; exit_code = $result.exit_code; finding_count = $findings.Count; findings = $findings; stdout = $result.output; error = if ($result.exit_code -eq 0) { $null } else { 'script_command_failed' } }
if ($sourceConfig.type -eq 'docker') { $payload.container = $sourceConfig.container }
Write-Json $payload
