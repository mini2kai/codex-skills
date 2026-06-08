param(
    [Parameter(Mandatory = $true)][string[]]$Paths
)

. "$PSScriptRoot\git_common.ps1"

try {
    Assert-NoGitOperationInProgress
    $repoRoot = Get-RepoRoot
    $current = Get-CurrentBranch
    $forbidden = @('.', '*', ':/', '--all', '-A', '-u')
    foreach ($path in $Paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { throw '路径不能为空。' }
        if ($forbidden -contains $path.Trim()) { throw "拒绝全量或模糊暂存表达：$path。请显式传文件路径。" }
        if ($path.Contains('*')) { throw "拒绝通配符路径：$path。请显式传文件路径。" }
    }
    Invoke-GitLines -Args (@('add', '--') + $Paths) | Out-Null
    $status = Split-Status
    Write-JsonResult @{
        ok = $true
        repo_root = $repoRoot
        current_branch = $current
        staged_paths_requested = $Paths
        staged_now = $status.staged
        unstaged_now = $status.unstaged
        untracked_now = $status.untracked
        message = '已按显式路径暂存。'
    }
} catch {
    Write-JsonResult @{ ok = $false; error = $_.Exception.Message }
    exit 1
}