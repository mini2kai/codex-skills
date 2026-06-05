param(
    [Parameter(Mandatory = $true)][string]$Url,
    [int]$TimeoutSeconds = 15
)

. "$PSScriptRoot\common.ps1"

try {
    $validation = Test-WebDemoHttpUrl -Url $Url -TimeoutSeconds $TimeoutSeconds
    $reason = $null
    if (-not $validation.ok) {
        if ($validation.statusCode -eq 502) { $reason = "cpolar 返回 502，通常是本地端口未启动或隧道未指向当前端口" }
        elseif ($validation.statusCode -eq 403) { $reason = "公网返回 403，Vite dev server 可能阻止了 cpolar Host；建议使用 vite preview" }
        else { $reason = $validation.error }
    }

    $exitCode = if ($validation.ok) { 0 } else { 1 }
    Write-WebDemoJson @{ ok = [bool]$validation.ok; url = $Url; validation = $validation; reason = $reason; message = if ($validation.ok) { "公网地址验证通过" } else { "公网地址验证未通过" } } $exitCode
}
catch {
    Write-WebDemoJson @{ ok = $false; error = "validate_public_failed"; url = $Url; message = $_.Exception.Message } 1
}

