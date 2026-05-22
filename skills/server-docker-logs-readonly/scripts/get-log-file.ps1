param(
    [Parameter(Mandatory = $true)] [string] $Target,
    [Parameter(Mandatory = $true)] [string] $Container,
    [string] $File = '',
    [int] $Tail = 200
)
. "$PSScriptRoot\common.ps1"
Assert-Tail -Tail $Tail
$targetConfig = Get-TargetConfig -Target $Target
$containerConfig = Get-ContainerConfig -TargetConfig $targetConfig -Container $Container
if ([string]::IsNullOrWhiteSpace($File)) { $File = $containerConfig.defaultLogFile }
$remote = New-TailLogFileCommand -Container $Container -LogDir $containerConfig.logDir -File $File -Tail $Tail -LogFilePrefix $containerConfig.logFilePrefix
$result = Invoke-TargetDockerRead -TargetConfig $targetConfig -RemoteCommand $remote
Write-Json @{ ok = ($result.exit_code -eq 0); target = $Target; container = $Container; log_dir = $containerConfig.logDir; file = $File; tail = $Tail; exit_code = $result.exit_code; stdout = $result.output; error = if ($result.exit_code -eq 0) { $null } else { 'script_command_failed' } }
