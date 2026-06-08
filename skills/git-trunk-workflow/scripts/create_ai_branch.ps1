param(
    [Parameter(Mandatory = $true)][string]$SourceBranch,
    [Parameter(Mandatory = $true)][string]$BranchName,
    [switch]$SyncSource,
    [switch]$CheckoutSource
)

. "$PSScriptRoot\git_common.ps1"

try {
    Assert-NoGitOperationInProgress
    if (-not (Test-AiBranchName -Branch $BranchName)) {
        throw "分支名不符合规则：$BranchName。格式应为 ai/<source>/<yyyymmdd>-<type>-<topic>。"
    }
    $repoRoot = Get-RepoRoot
    $current = Get-CurrentBranch
    $clean = Test-WorktreeClean
    if (-not $clean) {
        throw '工作区不干净，拒绝创建分支或同步来源分支；请先确认用户已有改动归属。'
    }
    $exists = & git rev-parse --verify --quiet "refs/heads/$BranchName" 2>$null
    if ($LASTEXITCODE -eq 0) {
        throw "本地分支已存在：$BranchName。"
    }

    $fetchRan = $false
    $pullFfOnlyRan = $false
    $sourceRemote = "origin/$SourceBranch"
    if ($SyncSource) {
        Invoke-GitLines -Args @('fetch', 'origin', '--prune') | Out-Null
        $fetchRan = $true
    }

    if ($current -ne $SourceBranch) {
        if (-not $CheckoutSource) {
            throw "当前分支是 $current，不是来源分支 $SourceBranch。未传 -CheckoutSource，拒绝自动切换。"
        }
        Invoke-GitLines -Args @('checkout', $SourceBranch) | Out-Null
        $current = Get-CurrentBranch
    }

    $sourceLocalSha = Get-FullSha -Ref $SourceBranch
    $sourceRemoteSha = Get-RemoteRefSha -RemoteRef $sourceRemote

    if ($SyncSource) {
        if (-not (Test-WorktreeClean)) { throw '切换后工作区不干净，拒绝 pull。' }
        $pullOutput = & git pull --ff-only 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "git pull --ff-only 失败，不自动 merge/rebase：$($pullOutput -join [Environment]::NewLine)"
        }
        $pullFfOnlyRan = $true
        $sourceLocalSha = Get-FullSha -Ref $SourceBranch
        $sourceRemoteSha = Get-RemoteRefSha -RemoteRef $sourceRemote
    }

    Invoke-GitLines -Args @('checkout', '-b', $BranchName) | Out-Null
    Write-JsonResult @{
        ok = $true
        repo_root = $repoRoot
        source_branch = $SourceBranch
        source_local_commit = $sourceLocalSha
        source_remote_ref = $sourceRemote
        source_remote_commit = $sourceRemoteSha
        fetch_ran = $fetchRan
        pull_ff_only_ran = $pullFfOnlyRan
        ai_branch = $BranchName
        ai_branch_head = Get-FullSha
        message = '已创建 AI 临时分支。'
    }
} catch {
    Write-JsonResult @{ ok = $false; error = $_.Exception.Message }
    exit 1
}