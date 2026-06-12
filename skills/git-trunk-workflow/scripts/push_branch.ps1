param(
    [string]$Remote = 'origin'
)

. "$PSScriptRoot\git_common.ps1"

try {
    Assert-NoGitOperationInProgress
    $repoRoot = Get-RepoRoot
    $branch = Get-CurrentBranch
    Assert-NotProtectedBranch -Branch $branch -Action 'push'
    $pushResult = Invoke-GitCapture -Args @('push', '-u', $Remote, $branch)
    if ($pushResult.ExitCode -ne 0) {
        $errorText = $pushResult.Lines -join [Environment]::NewLine
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
        message = '已 push 当前分支。'
    }
} catch {
    Write-JsonResult @{ ok = $false; error = $_.Exception.Message }
    exit 1
}
