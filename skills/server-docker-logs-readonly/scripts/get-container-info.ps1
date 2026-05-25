param(
    [Parameter(Mandatory = $true)] [string] $Target,
    [Parameter(Mandatory = $true)] [string] $Source
)
. "$PSScriptRoot\common.ps1"
$targetConfig = Get-TargetConfig -Target $Target
$sourceConfig = Get-SourceConfig -TargetConfig $targetConfig -Source $Source
if ($sourceConfig.type -ne 'docker') {
    Write-Json @{ ok = $false; error = 'source_type_not_supported'; source = $Source; source_type = $sourceConfig.type; message = 'get-container-info.ps1 只能用于 docker 类型日志源。' } 4
}
$remote = "docker inspect --format '{{.Name}} {{.Config.Image}} {{.State.Status}} {{.State.StartedAt}}' $($sourceConfig.container)"
$result = Invoke-SourceRead -SourceConfig $sourceConfig -RemoteCommand $remote -Audit @{ action = 'get-container-info' }
Write-Json @{ ok = ($result.exit_code -eq 0); target = $Target; source = $Source; source_type = $sourceConfig.type; account = $sourceConfig.account.name; container = $sourceConfig.container; log_dir = $sourceConfig.dir; exit_code = $result.exit_code; stdout = $result.output; error = if ($result.exit_code -eq 0) { $null } else { 'script_command_failed' } }
