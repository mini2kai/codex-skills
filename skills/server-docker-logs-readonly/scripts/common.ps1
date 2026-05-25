Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Json {
    param(
        [Parameter(Mandatory = $true)] [hashtable] $Payload,
        [int] $ExitCode = 0
    )
    $Payload | ConvertTo-Json -Depth 10
    exit $ExitCode
}

function Get-LocalConfigPath {
    Join-Path $PSScriptRoot 'targets.local.json'
}

function Get-SkillRoot {
    return (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
}

function Get-AuditLogDir {
    Join-Path (Get-SkillRoot) 'logs'
}

function Remove-OldAuditLogs {
    $logDir = Get-AuditLogDir
    if (-not (Test-Path -LiteralPath $logDir)) { return }
    $cutoff = (Get-Date).AddDays(-7)
    Get-ChildItem -LiteralPath $logDir -Filter 'server-access-*.jsonl' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force
}

function Write-AuditLog {
    param([Parameter(Mandatory = $true)] [hashtable] $Event)
    $logDir = Get-AuditLogDir
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    Remove-OldAuditLogs
    $date = Get-Date
    $payload = [ordered]@{
        time = $date.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
        skill = 'server-docker-logs-readonly'
    }
    foreach ($key in $Event.Keys) { $payload[$key] = $Event[$key] }
    $line = $payload | ConvertTo-Json -Compress -Depth 8
    $path = Join-Path $logDir ("server-access-{0}.jsonl" -f $date.ToString('yyyy-MM-dd'))
    Add-Content -LiteralPath $path -Value $line -Encoding UTF8
}

function Get-LocalConfig {
    $path = Get-LocalConfigPath
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Json @{ ok = $false; error = 'config_missing'; message = '缺少 skill 内置配置：scripts/targets.local.json'; next_action = '请在当前 skill 的 scripts/targets.local.json 中配置 targets、accounts 和 sources。' } 2
    }
    try {
        return Get-Content -Raw -LiteralPath $path | ConvertFrom-Json
    }
    catch {
        Write-Json @{ ok = $false; error = 'config_invalid'; message = $_.Exception.Message; next_action = '请修正 scripts/targets.local.json。该文件必须是标准 JSON，字段说明请写在 _fieldDescriptions 中。' } 2
    }
}

function Has-Property {
    param(
        [Parameter(Mandatory = $true)] $Object,
        [Parameter(Mandatory = $true)] [string] $Name
    )
    return ($null -ne $Object -and $Object.PSObject.Properties.Name.Contains($Name))
}

function Get-StringOrDefault {
    param($Object, [string] $Name, [string] $Default = '')
    $has = Has-Property -Object $Object -Name $Name
    if ($has -and -not [string]::IsNullOrWhiteSpace([string]$Object.$Name)) { return [string]$Object.$Name }
    return $Default
}

function Get-BoolOrDefault {
    param($Object, [string] $Name, [bool] $Default = $false)
    $has = Has-Property -Object $Object -Name $Name
    if ($has -and $null -ne $Object.$Name) { return [bool]$Object.$Name }
    return $Default
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

function Assert-SafeRelDir {
    param([Parameter(Mandatory = $true)] [string] $PathValue)
    if ($PathValue -notmatch '^[A-Za-z0-9_./-]{1,256}$' -or $PathValue.Contains('..') -or $PathValue.StartsWith('-') -or $PathValue.StartsWith('/') -or $PathValue.Contains('\')) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'logDir'; message = 'logDir 必须是容器内简单相对路径，不能包含 ..、绝对路径或 shell 特殊字符。' } 4
    }
}

function Assert-SafeAbsDir {
    param([Parameter(Mandatory = $true)] [string] $PathValue)
    if ($PathValue -notmatch '^/[A-Za-z0-9_./-]{1,255}$' -or $PathValue.Contains('..') -or $PathValue.Contains('//') -or $PathValue.Contains('\') -or $PathValue.EndsWith('/')) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'absDir'; message = 'absDir 必须是服务器上的简单绝对目录，不能包含 ..、反斜杠、重复斜杠或 shell 特殊字符。' } 4
    }
}

function Assert-SafeLogFile {
    param([Parameter(Mandatory = $true)] [string] $File)
    if ($File -notmatch '^[A-Za-z0-9_.-]{1,256}$' -or $File.StartsWith('-')) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'File'; message = 'File 必须是简单日志文件名，不能包含路径分隔符或 shell 特殊字符。' } 4
    }
}

function Assert-RequiredLogFile {
    param([string] $File)
    if ([string]::IsNullOrWhiteSpace($File)) {
        Write-Json @{ ok = $false; error = 'file_required'; field = 'File'; message = '必须指定 File。请先运行 list-log-files.ps1 查看日志目录下的文件名。' } 4
    }
    Assert-SafeLogFile -File $File
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
    $hasTargets = Has-Property -Object $config -Name 'targets'
    if (-not $hasTargets -or -not $config.targets.PSObject.Properties.Name.Contains($Target)) {
        Write-Json @{ ok = $false; error = 'target_not_found'; target = $Target; message = '本地未配置该 Target 别名。'; next_action = '请先运行 list-targets.ps1，并选择返回的目标别名。' } 3
    }
    return $config.targets.$Target
}

function Get-AccountConfig {
    param(
        [Parameter(Mandatory = $true)] $TargetConfig,
        [string] $Account = ''
    )
    $hasAccounts = Has-Property -Object $TargetConfig -Name 'accounts'
    if (-not $hasAccounts -or $null -eq $TargetConfig.accounts) {
        Write-Json @{ ok = $false; error = 'config_invalid'; message = 'Target 必须配置 accounts。' } 2
    }
    if ([string]::IsNullOrWhiteSpace($Account)) {
        $Account = Get-StringOrDefault -Object $TargetConfig -Name 'defaultAccount'
    }
    if ([string]::IsNullOrWhiteSpace($Account)) {
        Write-Json @{ ok = $false; error = 'config_invalid'; message = '未指定账号，且 Target 未配置 defaultAccount。' } 2
    }
    Assert-SafeName -Name $Account -Field 'Account'
    if (-not $TargetConfig.accounts.PSObject.Properties.Name.Contains($Account)) {
        Write-Json @{ ok = $false; error = 'account_not_found'; account = $Account; message = '本地未配置该 Account。'; next_action = '请运行 list-accounts.ps1 查看可用账号。' } 3
    }
    $entry = $TargetConfig.accounts.$Account
    return [pscustomobject]@{
        name = $Account
        description = Get-StringOrDefault -Object $entry -Name 'description'
        role = Get-StringOrDefault -Object $entry -Name 'role' -Default 'readonly'
        ssh = $entry.ssh
        permissions = $entry.permissions
    }
}

function Test-AccountPermission {
    param(
        [Parameter(Mandatory = $true)] $AccountConfig,
        [Parameter(Mandatory = $true)] [string] $Permission
    )
    $hasPermissions = Has-Property -Object $AccountConfig -Name 'permissions'
    if (-not $hasPermissions -or $null -eq $AccountConfig.permissions) { return $false }
    return (Get-BoolOrDefault -Object $AccountConfig.permissions -Name $Permission -Default $false)
}

function Assert-AccountPermission {
    param(
        [Parameter(Mandatory = $true)] $AccountConfig,
        [Parameter(Mandatory = $true)] [string] $Permission,
        [Parameter(Mandatory = $true)] [string] $SourceType
    )
    if (-not (Test-AccountPermission -AccountConfig $AccountConfig -Permission $Permission)) {
        Write-Json @{ ok = $false; error = 'account_permission_denied'; account = $AccountConfig.name; source_type = $SourceType; message = "账号 $($AccountConfig.name) 不允许使用 $SourceType 日志源。" } 4
    }
}

function Get-SourceConfig {
    param(
        [Parameter(Mandatory = $true)] $TargetConfig,
        [Parameter(Mandatory = $true)] [string] $Source
    )
    Assert-SafeName -Name $Source -Field 'Source'
    $hasSources = Has-Property -Object $TargetConfig -Name 'sources'
    if (-not $hasSources -or $null -eq $TargetConfig.sources) {
        Write-Json @{ ok = $false; error = 'config_invalid'; message = 'Target 必须配置 sources。' } 2
    }
    if (-not $TargetConfig.sources.PSObject.Properties.Name.Contains($Source)) {
        Write-Json @{ ok = $false; error = 'source_not_found'; source = $Source; message = '本地未配置该 Source。'; next_action = '请运行 list-sources.ps1 查看可用日志源。' } 3
    }
    $entry = $TargetConfig.sources.$Source
    $type = Get-StringOrDefault -Object $entry -Name 'type'
    if ($type -notin @('host_dir', 'docker')) {
        Write-Json @{ ok = $false; error = 'config_invalid'; source = $Source; message = 'Source type 只能是 host_dir 或 docker。' } 2
    }
    $accountName = Get-StringOrDefault -Object $entry -Name 'account' -Default (Get-StringOrDefault -Object $TargetConfig -Name 'defaultAccount')
    $accountConfig = Get-AccountConfig -TargetConfig $TargetConfig -Account $accountName
    if ($type -eq 'host_dir') {
        $absDir = Get-StringOrDefault -Object $entry -Name 'absDir'
        Assert-SafeAbsDir -PathValue $absDir
        Assert-AccountPermission -AccountConfig $accountConfig -Permission 'hostDir' -SourceType $type
        return [pscustomobject]@{ name = $Source; type = $type; description = Get-StringOrDefault -Object $entry -Name 'description'; account = $accountConfig; dir = $absDir; container = '' }
    }
    $container = Get-StringOrDefault -Object $entry -Name 'container'
    $logDir = Get-StringOrDefault -Object $entry -Name 'logDir' -Default 'logs'
    Assert-SafeName -Name $container -Field 'container'
    Assert-SafeRelDir -PathValue $logDir
    Assert-AccountPermission -AccountConfig $accountConfig -Permission 'docker' -SourceType $type
    return [pscustomobject]@{ name = $Source; type = $type; description = Get-StringOrDefault -Object $entry -Name 'description'; account = $accountConfig; dir = $logDir; container = $container }
}

function Assert-RemoteReadCommand {
    param([Parameter(Mandatory = $true)] [string] $RemoteCommand)
    if ($RemoteCommand -match "[`r`n]") {
        Write-Json @{ ok = $false; error = 'unsafe_remote_command'; message = '远程命令必须是单行命令。' } 4
    }
    if ($RemoteCommand -notmatch '^(cd -- /[A-Za-z0-9_./-]+ && |docker ps --format|docker inspect --format|docker exec [A-Za-z0-9_.-]+ /bin/sh -lc )') {
        Write-Json @{ ok = $false; error = 'unsafe_remote_command'; message = '远程命令不在只读日志命令白名单内。' } 4
    }
    $danger = @(
        ' rm ', ' rm -', ' mv ', ' cp ', ' touch ', ' mkdir ', ' rmdir ',
        ' chmod ', ' chown ', ' tee ', ' truncate ', ' sed -i', ' >', '>>',
        ' restart', ' stop', ' start', ' kill', ' systemctl ', ' service ',
        ' apt ', ' yum ', ' pip ', ' npm ', ' curl ', ' wget ', ' nc ', ' bash -i'
    )
    foreach ($item in $danger) {
        if ($RemoteCommand.IndexOf($item, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
            Write-Json @{ ok = $false; error = 'unsafe_remote_command'; message = "远程命令包含禁止片段：$item" } 4
        }
    }
}

function Invoke-AccountRead {
    param(
        [Parameter(Mandatory = $true)] $AccountConfig,
        [Parameter(Mandatory = $true)] [string] $RemoteCommand,
        [hashtable] $Audit = @{}
    )
    Assert-RemoteReadCommand -RemoteCommand $RemoteCommand
    $ssh = $AccountConfig.ssh
    if ($null -eq $ssh) { Write-Json @{ ok = $false; error = 'config_invalid'; account = $AccountConfig.name; message = 'Account 必须配置 ssh。' } 2 }
    if (-not $ssh.host) { Write-Json @{ ok = $false; error = 'config_invalid'; account = $AccountConfig.name; message = 'Account ssh.host 为必填项。' } 2 }
    $port = if ($ssh.port) { [string]$ssh.port } else { '22' }

    $hasPassword = $false
    $password = $null
    $hasPlainPassword = Has-Property -Object $ssh -Name 'password'
    if ($hasPlainPassword -and -not [string]::IsNullOrWhiteSpace([string]$ssh.password)) {
        $hasPassword = $true
        $password = [string]$ssh.password
    }
    $hasAuth = Has-Property -Object $ssh -Name 'auth'
    if ($hasAuth -and $null -ne $ssh.auth) {
        $hasAuthType = Has-Property -Object $ssh.auth -Name 'type'
        if ($hasAuthType -and [string]$ssh.auth.type -eq 'password') { $hasPassword = $true }
        $hasAuthPassword = Has-Property -Object $ssh.auth -Name 'password'
        if ($hasAuthPassword -and -not [string]::IsNullOrWhiteSpace([string]$ssh.auth.password)) { $password = [string]$ssh.auth.password }
    }

    if ($hasPassword) {
        if ([string]::IsNullOrWhiteSpace($password)) { Write-Json @{ ok = $false; error = 'config_invalid'; account = $AccountConfig.name; message = '已配置密码登录，但 password 为空。' } 2 }
        $hasUser = Has-Property -Object $ssh -Name 'user'
        if (-not $hasUser -or -not $ssh.user) { Write-Json @{ ok = $false; error = 'config_invalid'; account = $AccountConfig.name; message = '密码登录必须配置 ssh.user。' } 2 }
        $helper = Join-Path $PSScriptRoot 'ssh_run.py'
        if (-not (Test-Path -LiteralPath $helper)) { Write-Json @{ ok = $false; error = 'script_missing'; message = '缺少 skill 内置 SSH helper：scripts/ssh_run.py' } 2 }
        $pyArgs = @($helper, '--host', [string]$ssh.host, '--user', [string]$ssh.user, '--port', $port, '--password', $password, '--command', $RemoteCommand)
        Write-AuditLog -Event (@{
            event = 'server_read'
            account = $AccountConfig.name
            role = $AccountConfig.role
            host = [string]$ssh.host
            user = [string]$ssh.user
            port = $port
            command_kind = if ($RemoteCommand.StartsWith('docker ', [StringComparison]::Ordinal)) { 'docker' } else { 'host_dir' }
            remote_command = $RemoteCommand
        } + $Audit)
        $output = & python @pyArgs 2>&1
        return @{ exit_code = $LASTEXITCODE; output = (($output | Out-String).TrimEnd()) }
    }

    $sshArgs = @('-o', 'BatchMode=yes', '-o', 'ConnectTimeout=15')
    if ($port) { $sshArgs += @('-p', $port) }
    $hasIdentityFile = Has-Property -Object $ssh -Name 'identityFile'
    if ($hasIdentityFile -and $ssh.identityFile) { $sshArgs += @('-i', [string]$ssh.identityFile) }
    $dest = [string]$ssh.host
    $hasSshUser = Has-Property -Object $ssh -Name 'user'
    if ($hasSshUser -and $ssh.user) { $dest = "{0}@{1}" -f $ssh.user, $ssh.host }
    $sshArgs += @($dest, $RemoteCommand)
    Write-AuditLog -Event (@{
        event = 'server_read'
        account = $AccountConfig.name
        role = $AccountConfig.role
        host = [string]$ssh.host
        user = if ($hasSshUser) { [string]$ssh.user } else { '' }
        port = $port
        command_kind = if ($RemoteCommand.StartsWith('docker ', [StringComparison]::Ordinal)) { 'docker' } else { 'host_dir' }
        remote_command = $RemoteCommand
    } + $Audit)
    $output = & ssh @sshArgs 2>&1
    return @{ exit_code = $LASTEXITCODE; output = (($output | Out-String).TrimEnd()) }
}

function Quote-ShSingle {
    param([Parameter(Mandatory = $true)] [string] $Value)
    if ($Value.Contains("'")) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; message = 'shell 参数中不允许出现单引号。' } 4
    }
    return "'" + $Value + "'"
}

function New-DockerExecShellCommand {
    param([string] $Container, [string] $InnerCommand)
    Assert-SafeName -Name $Container -Field 'container'
    return "docker exec $Container /bin/sh -lc $(Quote-ShSingle $InnerCommand)"
}

function New-ListFilesInnerCommand {
    param([string] $Dir)
    return "cd -- $Dir && find . -maxdepth 1 -type f -exec basename {} \; 2>/dev/null | sort || true"
}

function New-TailInnerCommand {
    param([string] $Dir, [string] $File, [int] $Tail)
    Assert-RequiredLogFile -File $File
    Assert-Tail -Tail $Tail
    return "cd -- $Dir && tail -n $Tail -- $File 2>&1"
}

function New-SearchInnerCommand {
    param([string] $Dir, [string] $File, [string] $Keyword, [int] $MaxMatches)
    Assert-RequiredLogFile -File $File
    Assert-MaxMatches -MaxMatches $MaxMatches
    if ([string]::IsNullOrWhiteSpace($Keyword) -or $Keyword.Length -gt 200) {
        Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'Keyword'; message = 'Keyword 为必填项，且长度不能超过 200 个字符。' } 4
    }
    if ($Keyword -match '["`$\\]') { Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'Keyword'; message = 'Keyword 包含不支持的 shell 特殊字符。' } 4 }
    return "cd -- $Dir && grep -F -- `"$Keyword`" $File 2>/dev/null | tail -n $MaxMatches"
}

function New-RecentErrorsInnerCommand {
    param([string] $Dir, [string] $File, [int] $MaxMatches)
    Assert-RequiredLogFile -File $File
    Assert-MaxMatches -MaxMatches $MaxMatches
    return "cd -- $Dir && { grep -F -- ERROR $File 2>/dev/null; grep -F -- Exception $File 2>/dev/null; grep -F -- FATAL $File 2>/dev/null; grep -F -- Traceback $File 2>/dev/null; grep -F -- panic $File 2>/dev/null; grep -F -- failed $File 2>/dev/null; grep -F -- timeout $File 2>/dev/null; grep -F -- WARN $File 2>/dev/null; } | tail -n $MaxMatches"
}

function New-SourceReadCommand {
    param([Parameter(Mandatory = $true)] $SourceConfig, [Parameter(Mandatory = $true)] [string] $Action, [string] $File = '', [string] $Keyword = '', [int] $Tail = 200, [int] $MaxMatches = 200)
    if ($Action -eq 'list') { $inner = New-ListFilesInnerCommand -Dir $SourceConfig.dir }
    elseif ($Action -eq 'tail') { $inner = New-TailInnerCommand -Dir $SourceConfig.dir -File $File -Tail $Tail }
    elseif ($Action -eq 'search') { $inner = New-SearchInnerCommand -Dir $SourceConfig.dir -File $File -Keyword $Keyword -MaxMatches $MaxMatches }
    elseif ($Action -eq 'recent-errors') { $inner = New-RecentErrorsInnerCommand -Dir $SourceConfig.dir -File $File -MaxMatches $MaxMatches }
    else { Write-Json @{ ok = $false; error = 'invalid_parameter'; field = 'Action'; message = 'Action 不支持。' } 4 }

    if ($SourceConfig.type -eq 'docker') { return New-DockerExecShellCommand -Container $SourceConfig.container -InnerCommand $inner }
    return $inner
}

function Invoke-SourceRead {
    param([Parameter(Mandatory = $true)] $SourceConfig, [Parameter(Mandatory = $true)] [string] $RemoteCommand, [hashtable] $Audit = @{})
    $sourceAudit = @{
        source = $SourceConfig.name
        source_type = $SourceConfig.type
        dir = $SourceConfig.dir
        container = $SourceConfig.container
    } + $Audit
    return Invoke-AccountRead -AccountConfig $SourceConfig.account -RemoteCommand $RemoteCommand -Audit $sourceAudit
}
