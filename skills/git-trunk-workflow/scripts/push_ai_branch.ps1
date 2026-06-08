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
    if (Test-ProtectedBranch -Branch $branch) {
        throw "当前分支是受保护长期分支，拒绝 push：$branch。"
    }
    $output = & git push -u $Remote $branch 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git push 失败：$($output -join [Environment]::NewLine)"
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