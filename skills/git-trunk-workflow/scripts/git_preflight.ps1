param(
    [switch]$Fetch
)

. "$PSScriptRoot\git_common.ps1"

try {
    Assert-NoGitOperationInProgress
    $repoRoot = Get-RepoRoot
    $branch = Get-CurrentBranch
    $fetchRan = $false
    if ($Fetch) {
        Invoke-GitLines -Args @('fetch', 'origin', '--prune') | Out-Null
        $fetchRan = $true
    }
    $aheadBehind = Get-AheadBehind
    $status = Split-Status
    $aiBranches = @(Invoke-GitLines -Args @('branch', '--list', 'ai/*') | ForEach-Object { $_.Trim().TrimStart('*').Trim() } | Where-Object { $_ })
    $warning = Get-LongLivedBranchWarning -Branch $branch
    Write-JsonResult @{
        ok = $true
        repo_root = $repoRoot
        current_branch = $branch
        head = Get-HeadSha
        upstream = $aheadBehind.upstream
        ahead = $aheadBehind.ahead
        behind = $aheadBehind.behind
        fetch_ran = $fetchRan
        clean = (Test-WorktreeClean)
        staged = $status.staged
        unstaged = $status.unstaged
        untracked = $status.untracked
        ai_branches = $aiBranches
        warning = $warning
        next_action = '确认来源分支；工作区干净时可创建 ai/* 临时分支。'
    }
} catch {
    Write-JsonResult @{ ok = $false; error = $_.Exception.Message }
    exit 1
}