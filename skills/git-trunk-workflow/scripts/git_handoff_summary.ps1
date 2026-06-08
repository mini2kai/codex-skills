param(
    [string]$SourceBranch = '',
    [string]$PrimaryTarget = '',
    [string]$BackportTarget = ''
)

. "$PSScriptRoot\git_common.ps1"

function Get-DiffStatSafe {
    param([string]$Range)
    $output = & git diff --stat $Range 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($output)
}

function Get-LogSafe {
    param([string]$Range)
    $output = & git log --oneline $Range 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($output)
}

try {
    Assert-NoGitOperationInProgress
    $repoRoot = Get-RepoRoot
    $branch = Get-CurrentBranch
    $status = Split-Status
    $upstream = Get-Upstream
    $remotePushed = -not [string]::IsNullOrWhiteSpace($upstream)
    $commits = @()
    if ($SourceBranch) {
        $commits = Get-LogSafe -Range "$SourceBranch..HEAD"
    } else {
        $commits = Get-LogSafe -Range '-5'
    }
    $primaryDiff = @()
    if ($PrimaryTarget) { $primaryDiff = Get-DiffStatSafe -Range "$PrimaryTarget..HEAD" }
    $backportDiff = @()
    if ($BackportTarget) { $backportDiff = Get-DiffStatSafe -Range "$BackportTarget..HEAD" }
    $sourceCommit = ''
    $sourceRemoteRef = ''
    $sourceRemoteCommit = ''
    if ($SourceBranch) {
        $sourceCommit = Get-RemoteRefSha -RemoteRef $SourceBranch
        if (-not $sourceCommit) { $sourceCommit = Get-FullSha -Ref $SourceBranch }
        $sourceRemoteRef = "origin/$SourceBranch"
        $sourceRemoteCommit = Get-RemoteRefSha -RemoteRef $sourceRemoteRef
    }
    Write-JsonResult @{
        ok = $true
        repo_root = $repoRoot
        current_branch = $branch
        current_head = Get-FullSha
        source_branch = $SourceBranch
        source_commit = $sourceCommit
        source_remote_ref = $sourceRemoteRef
        source_remote_commit = $sourceRemoteCommit
        upstream = $upstream
        remote_pushed = $remotePushed
        commits = $commits
        clean = (Test-WorktreeClean)
        staged_remaining = $status.staged
        unstaged_remaining = $status.unstaged
        untracked_remaining = $status.untracked
        primary_target = $PrimaryTarget
        primary_target_diff_stat = $primaryDiff
        backport_target = $BackportTarget
        backport_target_diff_stat = $backportDiff
        required_handoff_fields = @('交付状态','来源分支','来源 commit','来源远端 commit','AI 临时分支','commit 列表','是否已 push','是否还有未提交改动','第一合并目标','是否建议回灌','验证结果','合并前风险点','发布注意事项','回滚建议','建议清理时间')
        cleanup_suggestion = '合并完成并确认回灌后 7-30 天清理 ai/* 分支；未合并超过 30-60 天提醒确认。'
        merge_warning = '脚本不执行长期分支 merge；如目标分支差异较大，优先建议 cherry-pick 或从目标分支重新开 ai/* 分支适配。'
    }
} catch {
    Write-JsonResult @{ ok = $false; error = $_.Exception.Message }
    exit 1
}