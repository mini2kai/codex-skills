param(
    [Parameter(Mandatory = $true)] [string] $Target,
    [Parameter(Mandatory = $true)] [string] $Source,
    [string] $File = '',
    [int] $Tail = 200
)
. "$PSScriptRoot\common.ps1"
Assert-Tail -Tail $Tail
$targetConfig = Get-TargetConfig -Target $Target
$sourceConfig = Get-SourceConfig -TargetConfig $targetConfig -Source $Source
$remote = New-SourceReadCommand -SourceConfig $sourceConfig -Action 'tail' -File $File -Tail $Tail
$result = Invoke-SourceRead -SourceConfig $sourceConfig -RemoteCommand $remote -Audit @{ action = 'get-log-file'; file = $File; tail = $Tail }
$payload = @{ ok = ($result.exit_code -eq 0); target = $Target; source = $Source; source_type = $sourceConfig.type; account = $sourceConfig.account.name; dir = $sourceConfig.dir; file = $File; tail = $Tail; exit_code = $result.exit_code; stdout = $result.output; error = if ($result.exit_code -eq 0) { $null } else { 'script_command_failed' } }
if ($sourceConfig.type -eq 'docker') { $payload.container = $sourceConfig.container }
Write-Json $payload
