param(
    [Parameter(Mandatory = $true)] [string] $Target,
    [Parameter(Mandatory = $true)] [string] $Container
)
. "$PSScriptRoot\common.ps1"
$targetConfig = Get-TargetConfig -Target $Target
$containerConfig = Get-ContainerConfig -TargetConfig $targetConfig -Container $Container
$remote = New-ListLogFilesCommand -Container $Container -LogDir $containerConfig.logDir -LogFilePrefix $containerConfig.logFilePrefix
$result = Invoke-TargetDockerRead -TargetConfig $targetConfig -RemoteCommand $remote
$files = if ([string]::IsNullOrWhiteSpace($result.output)) { @() } else { @($result.output -split "`r?`n") }
Write-Json @{ ok = ($result.exit_code -eq 0); target = $Target; container = $Container; log_dir = $containerConfig.logDir; log_file_prefix = $containerConfig.logFilePrefix; exit_code = $result.exit_code; files = $files; stdout = $result.output; error = if ($result.exit_code -eq 0) { $null } else { 'script_command_failed' } }
