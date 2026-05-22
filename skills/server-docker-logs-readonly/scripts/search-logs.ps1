param(
    [Parameter(Mandatory = $true)] [string] $Target,
    [Parameter(Mandatory = $true)] [string] $Container,
    [Parameter(Mandatory = $true)] [string] $Keyword,
    [string] $File = '',
    [int] $MaxMatches = 200
)
. "$PSScriptRoot\common.ps1"
Assert-MaxMatches -MaxMatches $MaxMatches
$targetConfig = Get-TargetConfig -Target $Target
$containerConfig = Get-ContainerConfig -TargetConfig $targetConfig -Container $Container
$remote = New-SearchLogFileCommand -Container $Container -LogDir $containerConfig.logDir -File $File -Keyword $Keyword -MaxMatches $MaxMatches
$result = Invoke-TargetDockerRead -TargetConfig $targetConfig -RemoteCommand $remote
$matches = if ([string]::IsNullOrWhiteSpace($result.output)) { @() } else { @($result.output -split "`r?`n") }
Write-Json @{ ok = ($result.exit_code -eq 0); target = $Target; container = $Container; log_dir = $containerConfig.logDir; file = $File; keyword = $Keyword; max_matches = $MaxMatches; exit_code = $result.exit_code; match_count = $matches.Count; matches = $matches; stdout = $result.output; error = if ($result.exit_code -eq 0) { $null } else { 'script_command_failed' } }
