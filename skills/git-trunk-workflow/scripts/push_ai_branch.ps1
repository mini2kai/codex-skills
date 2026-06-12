param(
    [string]$Remote = 'origin'
)

# 向后兼容包装：直接调用通用版 push_branch.ps1
& "$PSScriptRoot\push_branch.ps1" -Remote $Remote
exit $LASTEXITCODE
