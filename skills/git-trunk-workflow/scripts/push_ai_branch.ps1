param(
    [string]$Remote = 'origin'
)

. "$PSScriptRoot\git_common.ps1"

try {
    Assert-NoGitOperationInProgress
    $repoRoot = Get-RepoRoot
    $branch = Get-CurrentBranch
    if (-not (Test-AiBranchCurrent -Branch $branch)) {
        throw "当前分支不是 ai/*，拒绝 push：$branch。"
    }
    Assert-NotProtectedBranch -Branch $branch -Action 'push'
    $output = & git push -u $Remote $branch 2>&1
    if ($LASTEXITCODE -ne 0) {
        $errorText = $output -join [Environment]::NewLine
        $nextAction = 'git push 失败。'
        if ($errorText -match 'Proxy|proxy|CONNECT') {
            $nextAction = "网络代理问题，尝试：git -c http.proxy=`"`" -c https.proxy=`"`" push -u $Remote $branch"
        }
        Write-JsonResult @{ ok = $false; error = 'push_failed'; message = $errorText; next_action = $nextAction }
        exit 1
    }
    Write-GitAuditLog -Event @{
        event = 'push'
        remote = $Remote
        branch = $branch
        head = Get-FullSha
    }
    Write-JsonResult @{
        ok = $true
        repo_root = $repoRoot
        remote = $Remote
        branch = $branch
        head = Get-FullSha
        message = '已 push 当前 ai/* 临时分支。'
    }
} catch {
    Write-JsonResult @{ ok = $false; error = $_.Exception.Message }
    exit 1
}
