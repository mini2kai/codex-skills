Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# --- 围栏常量 ---
$script:AUDIT_RETENTION_DAYS = 7

function Write-JsonResult {
    param([Parameter(Mandatory = $true)][hashtable]$Data)
    $Data | ConvertTo-Json -Depth 8
}

function Get-GitAuditLogDir {
    Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path 'logs'
}

function Write-GitAuditLog {
    param([Parameter(Mandatory = $true)][hashtable]$Event)
    $logDir = Get-GitAuditLogDir
    if (-not (Test-Path -LiteralPath $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    # 清理过期日志
    Get-ChildItem -LiteralPath $logDir -Filter 'git-ops-*.jsonl' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$script:AUDIT_RETENTION_DAYS) } |
        Remove-Item -Force
    $date = Get-Date
    $payload = [ordered]@{
        time = $date.ToString('yyyy-MM-ddTHH:mm:ss.fffzzz')
        skill = 'git-trunk-workflow'
    }
    foreach ($key in $Event.Keys) { $payload[$key] = $Event[$key] }
    $line = $payload | ConvertTo-Json -Compress -Depth 8
    $path = Join-Path $logDir ("git-ops-{0}.jsonl" -f $date.ToString('yyyy-MM-dd'))
    Add-Content -LiteralPath $path -Value $line -Encoding UTF8
}

function Assert-NotProtectedBranch {
    param([Parameter(Mandatory = $true)][string]$Branch, [string]$Action = 'operation')
    if (Test-ProtectedBranch -Branch $Branch) {
        throw "当前分支 $Branch 是保护分支，拒绝 $Action。"
    }
}

function Invoke-GitCapture {
    param([Parameter(Mandatory = $true)][string[]]$Args)
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git @Args 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    return @{
        ExitCode = $exitCode
        Lines = @($output | ForEach-Object { $_.ToString() })
    }
}

function Invoke-GitLines {
    param([Parameter(Mandatory = $true)][string[]]$Args)
    $result = Invoke-GitCapture -Args $Args
    if ($result.ExitCode -ne 0) {
        throw "git $($Args -join ' ') failed: $($result.Lines -join [Environment]::NewLine)"
    }
    return @($result.Lines)
}

function Invoke-GitText {
    param([Parameter(Mandatory = $true)][string[]]$Args)
    return (Invoke-GitLines -Args $Args) -join [Environment]::NewLine
}

function Get-RepoRoot {
    return (Invoke-GitText -Args @('rev-parse', '--show-toplevel')).Trim()
}

function Get-CurrentBranch {
    return (Invoke-GitText -Args @('branch', '--show-current')).Trim()
}

function Get-HeadSha {
    param([string]$Ref = 'HEAD')
    return (Invoke-GitText -Args @('rev-parse', '--short=12', $Ref)).Trim()
}

function Get-FullSha {
    param([string]$Ref = 'HEAD')
    return (Invoke-GitText -Args @('rev-parse', $Ref)).Trim()
}

function Get-Upstream {
    $result = Invoke-GitCapture -Args @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
    if ($result.ExitCode -ne 0) { return '' }
    return ($result.Lines -join '').Trim()
}

function Get-StatusShortLines {
    return @(Invoke-GitLines -Args @('status', '--short'))
}

function Test-WorktreeClean {
    return @(Get-StatusShortLines).Count -eq 0
}

function Test-ProtectedBranch {
    param([Parameter(Mandatory = $true)][string]$Branch)
    return ($Branch -in @('main', 'master', 'dev', 'uat', 'prod', 'production', 'staging')) -or $Branch.StartsWith('release/') -or $Branch.StartsWith('hotfix/')
}

function Get-LongLivedBranchWarning {
    param([Parameter(Mandatory = $true)][string]$Branch)
    if (Test-ProtectedBranch -Branch $Branch) {
        return "当前分支 $Branch 是长期分支，禁止默认 push、merge 或直接提交交付。"
    }
    return ''
}

function Get-AheadBehind {
    $upstream = Get-Upstream
    if ([string]::IsNullOrWhiteSpace($upstream)) {
        return @{ upstream = ''; ahead = $null; behind = $null }
    }
    $counts = (Invoke-GitText -Args @('rev-list', '--left-right', '--count', 'HEAD...@{u}')).Trim() -split '\s+'
    return @{ upstream = $upstream; ahead = [int]$counts[0]; behind = [int]$counts[1] }
}

function Split-Status {
    $staged = New-Object System.Collections.Generic.List[string]
    $unstaged = New-Object System.Collections.Generic.List[string]
    $untracked = New-Object System.Collections.Generic.List[string]
    foreach ($line in Get-StatusShortLines) {
        if ($line.StartsWith('??')) {
            $untracked.Add($line.Substring(3))
            continue
        }
        if ($line.Length -ge 3) {
            if ($line[0] -ne ' ') { $staged.Add($line.Substring(3)) }
            if ($line[1] -ne ' ') { $unstaged.Add($line.Substring(3)) }
        }
    }
    return @{ staged = @($staged); unstaged = @($unstaged); untracked = @($untracked) }
}

function Assert-NoGitOperationInProgress {
    $gitDir = (Invoke-GitText -Args @('rev-parse', '--git-dir')).Trim()
    $markers = @('MERGE_HEAD', 'REBASE_HEAD', 'CHERRY_PICK_HEAD', 'BISECT_LOG')
    foreach ($marker in $markers) {
        if (Test-Path (Join-Path $gitDir $marker)) {
            throw "检测到 Git 中间状态 $marker，先处理完成后再执行此脚本。"
        }
    }
    if (Test-Path (Join-Path $gitDir 'rebase-merge')) { throw '检测到 rebase-merge 中间状态。' }
    if (Test-Path (Join-Path $gitDir 'rebase-apply')) { throw '检测到 rebase-apply 中间状态。' }
}

function Get-RemoteRefSha {
    param([Parameter(Mandatory = $true)][string]$RemoteRef)
    $result = Invoke-GitCapture -Args @('rev-parse', '--verify', '--quiet', $RemoteRef)
    if ($result.ExitCode -ne 0) { return '' }
    return ($result.Lines -join '').Trim()
}
