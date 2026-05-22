param(
    [Parameter(Mandatory = $true)] [string] $Target,
    [Parameter(Mandatory = $true)] [string] $Container
)
. "$PSScriptRoot\common.ps1"
$targetConfig = Get-TargetConfig -Target $Target
$containerConfig = Get-ContainerConfig -TargetConfig $targetConfig -Container $Container
$remote = "docker inspect --format '{{.Name}} {{.Config.Image}} {{.State.Status}} {{.State.StartedAt}}' $Container"
$result = Invoke-TargetDockerRead -TargetConfig $targetConfig -RemoteCommand $remote
Write-Json @{ ok = ($result.exit_code -eq 0); target = $Target; container = $Container; log_dir = $containerConfig.logDir; exit_code = $result.exit_code; stdout = $result.output; error = if ($result.exit_code -eq 0) { $null } else { 'script_command_failed' } }
