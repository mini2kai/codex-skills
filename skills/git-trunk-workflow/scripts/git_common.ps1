Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-JsonResult {
    param([Parameter(Mandatory = $true)][hashtable]$Data)
    $Data | ConvertTo-Json -Depth 8
}

function Invoke-GitLines {
    param([Parameter(Mandatory = $true)][string[]]$Args)
    $output = & git @Args 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Args -join ' ') failed: $($output -join [Environment]::NewLine)"
    }
    return @($output)
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
    $output = & git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($LASTEXITCODE -ne 0) { return '' }
    return ($output -join '').Trim()
}

function Get-StatusShortLines {
    return @(Invoke-GitLines -Args @('status', '--short'))
}

function Test-WorktreeClean {
    return (Get-StatusShortLines).Count -eq 0
}

function Test-AiBranchName {
    param([Parameter(Mandatory = $true)][string]$Branch)
    return $Branch -match '^ai/[A-Za-z0-9._-]+/[0-9]{8}-(fix|feat|bug|hotfix|docs|chore|refactor)-[A-Za-z0-9._-]+$'
}

function Test-AiBranchCurrent {
    param([Parameter(Mandatory = $true)][string]$Branch)
    return $Branch -like 'ai/*'
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
    $output = & git rev-parse --verify --quiet $RemoteRef 2>$null
    if ($LASTEXITCODE -ne 0) { return '' }
    return ($output -join '').Trim()
}