param(
    [Parameter(Mandatory = $true)][string]$Title,
    [string[]]$Bullets = @()
)

. "$PSScriptRoot\git_common.ps1"

try {
    Assert-NoGitOperationInProgress
    $repoRoot = Get-RepoRoot
    $branch = Get-CurrentBranch
    Assert-NotProtectedBranch -Branch $branch -Action 'commit'
    Assert-CommitTitlePrefix -Title $Title
    $status = Split-Status
    if ($status.staged.Count -eq 0) {
        throw '暂存区为空，拒绝 commit。请先显式暂存本次任务相关文件。'
    }
    $commitArgs = @('commit', '-m', $Title)
    foreach ($bullet in $Bullets) {
        if (-not [string]::IsNullOrWhiteSpace($bullet)) {
            $text = $bullet.Trim()
            if (-not $text.StartsWith('-')) { $text = "- $text" }
            $commitArgs += @('-m', $text)
        }
    }
    $commitResult = Invoke-GitCapture -Args $commitArgs
    if ($commitResult.ExitCode -ne 0) {
        throw "git commit 失败：$($commitResult.Lines -join [Environment]::NewLine)"
    }
    $postStatus = Split-Status
    Write-GitAuditLog -Event @{
        event = 'commit'
        branch = $branch
        commit = Get-FullSha
        title = $Title
        files = $status.staged
    }
    Write-JsonResult @{
        ok = $true
        repo_root = $repoRoot
        current_branch = $branch
        commit = Get-FullSha
        commit_short = Get-HeadSha
        title = $Title
        bullets = $Bullets
        committed_files = $status.staged
        unstaged_remaining = $postStatus.unstaged
        untracked_remaining = $postStatus.untracked
        message = '已创建中文详细 commit。'
    }
} catch {
    Write-JsonResult @{ ok = $false; error = $_.Exception.Message }
    exit 1
}
