param(
    [Parameter(Mandatory = $true)][string]$SourceBranch,
    [Parameter(Mandatory = $true)][string]$BranchName,
    [switch]$SyncSource,
    [switch]$NoCheckout
)

# 向后兼容包装：直接调用通用版 create_branch.ps1
$extraArgs = @()
if ($SyncSource) { $extraArgs += '-SyncSource' }
if ($NoCheckout) { $extraArgs += '-NoCheckout' }
& "$PSScriptRoot\create_branch.ps1" -SourceBranch $SourceBranch -BranchName $BranchName @extraArgs
exit $LASTEXITCODE
