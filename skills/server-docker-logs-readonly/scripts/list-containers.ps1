param([Parameter(Mandatory = $true)] [string] $Target)
. "$PSScriptRoot\common.ps1"
$targetConfig = Get-TargetConfig -Target $Target
$result = Invoke-TargetDockerRead -TargetConfig $targetConfig -RemoteCommand "docker ps --format 'table {{.ID}}	{{.Names}}	{{.Image}}	{{.Status}}'"
Write-Json @{ ok = ($result.exit_code -eq 0); target = $Target; exit_code = $result.exit_code; stdout = $result.output; error = if ($result.exit_code -eq 0) { $null } else { 'script_command_failed' } }
