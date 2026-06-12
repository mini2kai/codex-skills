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

function Get-AheadBehindRange {
    param([string]$Ref1, [string]$Ref2)
    $output = & git rev-list --left-right --count "$Ref1...$Ref2" 2>$null
    if ($LASTEXITCODE -ne 0) { return @{ ahead = $null; behind = $null } }
    $counts = ($output -join '').Trim() -split '\s+'
    return @{ ahead = [int]$counts[0]; behind = [int]$counts[1] }
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
    $primaryAheadBehind = @{ ahead = $null; behind = $null }
    if ($PrimaryTarget) {
        $primaryDiff = Get-DiffStatSafe -Range "$PrimaryTarget..HEAD"
        $primaryAheadBehind = Get-AheadBehindRange -Ref1 'HEAD' -Ref2 $PrimaryTarget
    }
    $backportDiff = @()
    if ($BackportTarget) { $backportDiff = Get-DiffStatSafe -Range "$BackportTarget..HEAD" }

    # 来源分支领先当前分支多少（开发期间来源有新提交）
    $sourceAheadOfAi = $null
    $sourceCommit = ''
    $sourceRemoteRef = ''
    $sourceRemoteCommit = ''
    if ($SourceBranch) {
        $sourceCommit = Get-RemoteRefSha -RemoteRef $SourceBranch
        if (-not $sourceCommit) { $sourceCommit = Get-FullSha -Ref $SourceBranch }
        $sourceRemoteRef = "origin/$SourceBranch"
        $sourceRemoteCommit = Get-RemoteRefSha -RemoteRef $sourceRemoteRef
        # 来源分支比当前 ai 分支领先多少
        $sourceVsAi = Get-AheadBehindRange -Ref1 $SourceBranch -Ref2 'HEAD'
        $sourceAheadOfAi = $sourceVsAi.ahead
    }

    Write-GitAuditLog -Event @{
        event = 'handoff_summary'
        branch = $branch
        source_branch = $SourceBranch
        primary_target = $PrimaryTarget
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
        source_ahead_of_ai = $sourceAheadOfAi
        source_ahead_warning = if ($sourceAheadOfAi -and $sourceAheadOfAi -gt 0) { "来源分支 $SourceBranch 比当前分支领先 $sourceAheadOfAi 个 commit，合并时可能有冲突。" } else { $null }
        upstream = $upstream
        remote_pushed = $remotePushed
        commits = $commits
        clean = (Test-WorktreeClean)
        staged_remaining = $status.staged
        unstaged_remaining = $status.unstaged
        untracked_remaining = $status.untracked
        primary_target = $PrimaryTarget
        primary_target_diff_stat = $primaryDiff
        primary_target_ahead = $primaryAheadBehind.ahead
        primary_target_behind = $primaryAheadBehind.behind
        backport_target = $BackportTarget
        backport_target_diff_stat = $backportDiff
        cleanup_suggestion = '合并完成并确认回灌后 7-30 天清理临时分支；未合并超过 30-60 天提醒确认。'
        merge_warning = '脚本不执行长期分支 merge；如目标分支差异较大，优先建议 cherry-pick 或从目标分支重新开临时分支适配。'
    }
} catch {
    Write-JsonResult @{ ok = $false; error = $_.Exception.Message }
    exit 1
}
