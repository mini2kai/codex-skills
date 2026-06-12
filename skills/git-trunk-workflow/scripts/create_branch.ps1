param(
    [Parameter(Mandatory = $true)][string]$SourceBranch,
    [Parameter(Mandatory = $true)][string]$BranchName,
    [switch]$SyncSource,
    [switch]$NoCheckout
)

. "$PSScriptRoot\git_common.ps1"

try {
    Assert-NoGitOperationInProgress
    Assert-NotProtectedBranch -Branch $BranchName -Action 'create'
    $repoRoot = Get-RepoRoot
    $current = Get-CurrentBranch
    $clean = Test-WorktreeClean
    if (-not $clean) {
        throw '工作区不干净，拒绝创建分支或同步来源分支；请先确认用户已有改动归属。'
    }
    $exists = Invoke-GitCapture -Args @('rev-parse', '--verify', '--quiet', "refs/heads/$BranchName")
    if ($exists.ExitCode -eq 0) {
        throw "本地分支已存在：$BranchName。禁止改用 git checkout -b 或 git switch -c 绕过脚本；请确认是否切换到已有分支、改用新分支名，或清理后重新运行本脚本。"
    }
    $fetchRan = $false
    $pullFfOnlyRan = $false
    $sourceRemote = "origin/$SourceBranch"
    if ($SyncSource) {
        Invoke-GitLines -Args @('fetch', 'origin', '--prune') | Out-Null
        $fetchRan = $true
    }

    $remoteNewBranch = "origin/$BranchName"
    $remoteExists = Invoke-GitCapture -Args @('rev-parse', '--verify', '--quiet', $remoteNewBranch)
    if ($remoteExists.ExitCode -eq 0) {
        throw "远端分支已存在：$remoteNewBranch。禁止改用 git checkout -b 或 git switch -c 绕过脚本；请确认是否跟踪远端已有分支或改用新分支名。"
    }

    if ($current -ne $SourceBranch) {
        if ($NoCheckout) {
            throw "当前分支是 $current，不是来源分支 $SourceBranch。已指定 -NoCheckout，拒绝切换。"
        }
        Invoke-GitLines -Args @('checkout', $SourceBranch) | Out-Null
        $current = Get-CurrentBranch
    }

    $sourceLocalSha = Get-FullSha -Ref $SourceBranch
    $sourceRemoteSha = Get-RemoteRefSha -RemoteRef $sourceRemote

    if ($SyncSource) {
        if (-not (Test-WorktreeClean)) { throw '切换后工作区不干净，拒绝 pull。' }
        $pullResult = Invoke-GitCapture -Args @('pull', '--ff-only')
        if ($pullResult.ExitCode -ne 0) {
            throw "git pull --ff-only 失败，不自动 merge/rebase：$($pullResult.Lines -join [Environment]::NewLine)"
        }
        $pullFfOnlyRan = $true
        $sourceLocalSha = Get-FullSha -Ref $SourceBranch
        $sourceRemoteSha = Get-RemoteRefSha -RemoteRef $sourceRemote
    }

    Invoke-GitLines -Args @('checkout', '-b', $BranchName) | Out-Null
    Write-GitAuditLog -Event @{
        event = 'create_branch'
        source_branch = $SourceBranch
        new_branch = $BranchName
        source_commit = $sourceLocalSha
        fetch_ran = $fetchRan
        pull_ff_only_ran = $pullFfOnlyRan
    }
    Write-JsonResult @{
        ok = $true
        repo_root = $repoRoot
        source_branch = $SourceBranch
        source_local_commit = $sourceLocalSha
        source_remote_ref = $sourceRemote
        source_remote_commit = $sourceRemoteSha
        fetch_ran = $fetchRan
        pull_ff_only_ran = $pullFfOnlyRan
        new_branch = $BranchName
        new_branch_head = Get-FullSha
        message = '已创建临时分支。'
    }
} catch {
    Write-JsonResult @{
        ok = $false
        error = $_.Exception.Message
        native_git_fallback_forbidden = $true
        blocked_next_step = '停止当前 Git 操作，不要手动执行 git checkout -b、git switch -c、git add、git commit 或 git push；向用户说明脚本错误并在修正原因后重新运行本脚本。'
    }
    exit 1
}
