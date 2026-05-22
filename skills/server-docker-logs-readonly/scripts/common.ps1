Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Json {
    param(
        [Parameter(Mandatory = $true)] [hashtable] $Payload,
        [int] $ExitCode = 0
    )
    $Payload | ConvertTo-Json -Depth 8
    exit $ExitCode
}

function Get-RepoRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
}

function Get-LocalConfigPath {
    Join-Path (Get-RepoRoot) 'custom_script\server-docker-logs-readonly\targets.local.json'
}

function Get-LocalConfig {
    $path = Get-LocalConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Json @{ ok = $false; error = 'config_missing'; message = '缺少本地配置：custom_script/server-docker-logs-readonly/targets.local.json'; next_action = '请按 skill 内 scripts/targets.local.json 的格式，在 custom_script/server-docker-logs-readonly/ 下创建本地 targets.local.json，并确认它不提交到 Git。' } 2
    }
    try {
        return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    }
    catch {
        Write-Json @{ ok = $false; error = 'config_invalid'; message = $_.Exception.Message; next_action = '请修正本地 JSON 配置语法。' } 2
    }
}

function Assert-SafeName {
    param(
        [Parameter(Mandatory = $true)] [string] $Name,
        [Parameter(Mandatory = $true)] [string] $Field
    )
    if ($Name -notmatch '^[A-Za-z0-9_.-]{1,160}$') {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; field = $Field; message = "$Field 只能包含字母、数字、下划线、点和连字符。" } 4
    }
}

function Assert-SafePath {
    param(
        [Parameter(Mandatory = $true)] [string] $PathValue,
        [Parameter(Mandatory = $true)] [string] $Field
    )
    if ($PathValue -notmatch '^[A-Za-z0-9_./-]{1,256}$' -or $PathValue.Contains('..') -or $PathValue.StartsWith('-') -or $PathValue.StartsWith('/') -or $PathValue.Contains('\')) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; field = $Field; message = "$Field 必须是简单配置路径，不能包含 .. 或 shell 特殊字符。" } 4
    }
}

function Assert-SafeLogFile {
    param(
        [Parameter(Mandatory = $true)] [string] $File,
        [string] $LogFilePrefix = ''
    )
    if ($File -notmatch '^[A-Za-z0-9_.-]{1,256}$' -or $File.StartsWith('-')) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'File'; message = 'File 必须是简单日志文件名，不能包含路径分隔符或 shell 特殊字符。' } 4
    }
    if (-not [string]::IsNullOrWhiteSpace($LogFilePrefix) -and -not $File.StartsWith($LogFilePrefix, [StringComparison]::Ordinal)) {
        Write-Json @{ ok = $false; error = 'log_file_not_allowed'; file = $File; message = 'File 不匹配本地配置允许的日志文件前缀。' } 4
    }
}

function Assert-Tail {
    param([int] $Tail)
    if ($Tail -lt 1 -or $Tail -gt 5000) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'Tail'; message = 'Tail 必须在 1 到 5000 之间。' } 4
    }
}

function Assert-MaxMatches {
    param([int] $MaxMatches)
    if ($MaxMatches -lt 1 -or $MaxMatches -gt 1000) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'MaxMatches'; message = 'MaxMatches 必须在 1 到 1000 之间。' } 4
    }
}


function Get-TargetConfig {
    param([Parameter(Mandatory = $true)] [string] $Target)
    Assert-SafeName -Name $Target -Field 'Target'
    $config = Get-LocalConfig
    if (-not $config.targets.PSObject.Properties.Name.Contains($Target)) {
        Write-Json @{ ok = $false; error = 'target_not_found'; target = $Target; message = '本地未配置该 Target 别名。'; next_action = '请先运行 list-targets.ps1，并选择返回的目标别名。' } 3
    }
    return $config.targets.$Target
}

function Get-ContainerConfig {
    param(
        [Parameter(Mandatory = $true)] $TargetConfig,
        [Parameter(Mandatory = $true)] [string] $Container
    )
    Assert-SafeName -Name $Container -Field 'Container'
    $default = [pscustomobject]@{
        logDir = 'logs'
        logFilePrefix = 'MODULE_INSTANCE.log'
        defaultLogFile = 'MODULE_INSTANCE.log'
        description = ''
    }
    if (-not $TargetConfig.PSObject.Properties.Name.Contains('containers') -or $null -eq $TargetConfig.containers) {
        return $default
    }
    $containers = $TargetConfig.containers
    if ($containers -is [System.Array]) {
        if ($containers -notcontains $Container) {
            Write-Json @{ ok = $false; error = 'container_not_allowed'; container = $Container; message = '该 Container 不在此 Target 的本地白名单内。'; next_action = '请运行 list-containers.ps1 查看允许的容器，或更新本地配置。' } 4
        }
        return $default
    }
    if ($containers.PSObject.Properties.Name.Contains($Container)) {
        $entry = $containers.$Container
        $logDir = if ($entry.PSObject.Properties.Name.Contains('logDir') -and $entry.logDir) { [string]$entry.logDir } else { 'logs' }
        $prefix = if ($entry.PSObject.Properties.Name.Contains('logFilePrefix') -and $entry.logFilePrefix) { [string]$entry.logFilePrefix } else { 'MODULE_INSTANCE.log' }
        $defaultFile = if ($entry.PSObject.Properties.Name.Contains('defaultLogFile') -and $entry.defaultLogFile) { [string]$entry.defaultLogFile } else { $prefix }
        Assert-SafePath -PathValue $logDir -Field 'logDir'
        Assert-SafeLogFile -File $prefix
        Assert-SafeLogFile -File $defaultFile -LogFilePrefix $prefix
        return [pscustomobject]@{
            logDir = $logDir
            logFilePrefix = $prefix
            defaultLogFile = $defaultFile
            description = if ($entry.PSObject.Properties.Name.Contains('description')) { [string]$entry.description } else { '' }
        }
    }
    Write-Json @{ ok = $false; error = 'container_not_allowed'; container = $Container; message = '该 Container 不在此 Target 的本地白名单内。'; next_action = '请运行 list-containers.ps1 查看允许的容器，或更新本地配置。' } 4
}


function Assert-RemoteReadCommand {
    param([Parameter(Mandatory = $true)] [string] $RemoteCommand)
    if ($RemoteCommand -match "[`r`n]") {
        Write-Json @{ ok = $false; error = 'unsafe_remote_command'; message = '远程命令必须是单行命令。' } 4
    }
    if ($RemoteCommand -notmatch '^(docker ps --format|docker inspect --format|docker exec [A-Za-z0-9_.-]+ /bin/sh -lc )') {
        Write-Json @{ ok = $false; error = 'unsafe_remote_command'; message = '远程命令不在只读 Docker 命令白名单内。' } 4
    }
    $danger = @(
        ' rm ', ' rm -', ' mv ', ' cp ', ' touch ', ' mkdir ', ' rmdir ',
        ' chmod ', ' chown ', ' tee ', ' truncate ', ' sed -i',
        ' restart', ' stop', ' start', ' kill', ' systemctl ', ' service ',
        ' apt ', ' yum ', ' pip ', ' npm ', ' curl ', ' wget ', ' nc ', ' bash -i'
    )
    foreach ($item in $danger) {
        if ($RemoteCommand.IndexOf($item, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-Json @{ ok = $false; error = 'unsafe_remote_command'; message = "远程命令包含禁止片段：$item" } 4
        }
    }
}

function Invoke-TargetDockerRead {
    param(
        [Parameter(Mandatory = $true)] $TargetConfig,
        [Parameter(Mandatory = $true)] [string] $RemoteCommand
    )
    Assert-RemoteReadCommand -RemoteCommand $RemoteCommand
    if (-not $TargetConfig.PSObject.Properties.Name.Contains('ssh')) {
        Write-Json @{ ok = $false; error = 'config_invalid'; message = 'Target 配置必须包含 ssh 设置。' } 2
    }
    $ssh = $TargetConfig.ssh
    if (-not $ssh.host) {
        Write-Json @{ ok = $false; error = 'config_invalid'; message = 'Target ssh.host 为必填项。' } 2
    }

    $hasPassword = $false
    $password = $null
    if ($ssh.PSObject.Properties.Name.Contains('password') -and -not [string]::IsNullOrWhiteSpace([string]$ssh.password)) {
        $hasPassword = $true
        $password = [string]$ssh.password
    }
    if ($ssh.PSObject.Properties.Name.Contains('auth') -and $null -ne $ssh.auth) {
        if ($ssh.auth.PSObject.Properties.Name.Contains('type') -and [string]$ssh.auth.type -eq 'password') {
            $hasPassword = $true
        }
        if ($ssh.auth.PSObject.Properties.Name.Contains('password') -and -not [string]::IsNullOrWhiteSpace([string]$ssh.auth.password)) {
            $password = [string]$ssh.auth.password
        }
    }

    if ($hasPassword) {
        if ([string]::IsNullOrWhiteSpace($password)) {
            Write-Json @{ ok = $false; error = 'config_invalid'; message = '已配置密码登录，但 password 为空。' } 2
        }
        $helper = Join-Path $PSScriptRoot 'ssh_run.py'
        if (-not (Test-Path -LiteralPath $helper)) {
            Write-Json @{ ok = $false; error = 'script_missing'; message = '缺少 skill 内置 SSH helper：scripts/ssh_run.py' } 2
        }
        if (-not ($ssh.PSObject.Properties.Name.Contains('user') -and $ssh.user)) { Write-Json @{ ok = $false; error = 'config_invalid'; message = '密码登录必须配置 Target ssh.user。' } 2 }
        $pyArgs = @($helper, '--host', [string]$ssh.host, '--user', [string]$ssh.user, '--port', [string]$ssh.port, '--password', $password, '--command', $RemoteCommand)
        $output = & python @pyArgs 2>&1
        $code = $LASTEXITCODE
        return @{ exit_code = $code; output = (($output | Out-String).TrimEnd()) }
    }

    $sshArgs = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15')
    if ($ssh.PSObject.Properties.Name.Contains('port') -and $ssh.port) { $sshArgs += @('-p', [string]$ssh.port) }
    if ($ssh.PSObject.Properties.Name.Contains('identityFile') -and $ssh.identityFile) { $sshArgs += @('-i', [string]$ssh.identityFile) }
    $dest = [string]$ssh.host
    if ($ssh.PSObject.Properties.Name.Contains('user') -and $ssh.user) { $dest = "{0}@{1}" -f $ssh.user, $ssh.host }
    $sshArgs += @($dest, $RemoteCommand)
    $output = & ssh @sshArgs 2>&1
    $code = $LASTEXITCODE
    return @{ exit_code = $code; output = (($output | Out-String).TrimEnd()) }
}

function Quote-ShSingle {
    param([Parameter(Mandatory = $true)] [string] $Value)
    if ($Value.Contains("'")) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; message = 'shell 参数中不允许出现单引号。' } 4
    }
    return "'" + $Value + "'"
}

function New-DockerExecShellCommand {
    param(
        [Parameter(Mandatory = $true)] [string] $Container,
        [Parameter(Mandatory = $true)] [string] $InnerCommand
    )
    Assert-SafeName -Name $Container -Field 'Container'
    return "docker exec $Container /bin/sh -lc $(Quote-ShSingle $InnerCommand)"
}

function New-ListLogFilesCommand {
    param([string] $Container, [string] $LogDir, [string] $LogFilePrefix)
    Assert-SafePath -PathValue $LogDir -Field 'logDir'
    Assert-SafeLogFile -File $LogFilePrefix
    $inner = "cd -- $LogDir && ls -1 -- $LogFilePrefix* 2>/dev/null || true"
    return New-DockerExecShellCommand -Container $Container -InnerCommand $inner
}

function New-TailLogFileCommand {
    param([string] $Container, [string] $LogDir, [string] $File, [int] $Tail, [string] $LogFilePrefix)
    Assert-SafePath -PathValue $LogDir -Field 'logDir'
    Assert-SafeLogFile -File $File -LogFilePrefix $LogFilePrefix
    Assert-Tail -Tail $Tail
    $inner = "cd -- $LogDir && tail -n $Tail -- $File 2>&1"
    return New-DockerExecShellCommand -Container $Container -InnerCommand $inner
}

function New-SearchLogFileCommand {
    param([string] $Container, [string] $LogDir, [string] $File, [string] $Keyword, [int] $MaxMatches, [string] $LogFilePrefix)
    Assert-SafePath -PathValue $LogDir -Field 'logDir'
    Assert-SafeLogFile -File $File -LogFilePrefix $LogFilePrefix
    Assert-MaxMatches -MaxMatches $MaxMatches
    if ([string]::IsNullOrWhiteSpace($Keyword) -or $Keyword.Length -gt 200) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'Keyword'; message = 'Keyword 为必填项，且长度不能超过 200 个字符。' } 4
    }
    if ($Keyword -match '["`$\\]') { Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'Keyword'; message = 'Keyword 包含不支持的 shell 特殊字符。' } 4 }
    $inner = "cd -- $LogDir && grep -F -- `"$Keyword`" $File 2>/dev/null | tail -n $MaxMatches"
    return New-DockerExecShellCommand -Container $Container -InnerCommand $inner
}

function New-RecentErrorsCommand {
    param([string] $Container, [string] $LogDir, [string] $File, [int] $MaxMatches, [string] $LogFilePrefix)
    Assert-SafePath -PathValue $LogDir -Field 'logDir'
    Assert-SafeLogFile -File $File -LogFilePrefix $LogFilePrefix
    Assert-MaxMatches -MaxMatches $MaxMatches
    $inner = "cd -- $LogDir && { grep -F -- ERROR $File 2>/dev/null; grep -F -- Exception $File 2>/dev/null; grep -F -- FATAL $File 2>/dev/null; grep -F -- Traceback $File 2>/dev/null; grep -F -- panic $File 2>/dev/null; grep -F -- failed $File 2>/dev/null; grep -F -- timeout $File 2>/dev/null; grep -F -- WARN $File 2>/dev/null; } | tail -n $MaxMatches"
    return New-DockerExecShellCommand -Container $Container -InnerCommand $inner
}
