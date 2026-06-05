param(
    [string]$ProjectPath = ".",
    [int]$Port = 9999,
    [string]$PublicUrl
)

. "$PSScriptRoot\common.ps1"

function ConvertFrom-WebDemoJsonText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { return $Text | ConvertFrom-Json } catch { return $null }
}

try {
    $resolvedProject = Resolve-WebDemoPath -Path $ProjectPath
    $runtimeState = Read-WebDemoRuntimeState
    $connections = @(Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue)
    $pids = @($connections | Select-Object -ExpandProperty OwningProcess -Unique | Where-Object { $_ -gt 0 })
    $localUrl = "http://localhost:$Port/"
    $localValidation = Test-WebDemoHttpUrl -Url $localUrl -TimeoutSeconds 10

    $detectScript = Join-Path $PSScriptRoot "detect-cpolar.ps1"
    $detectCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value $detectScript) -Port $Port"
    $detectStep = Invoke-WebDemoCommand -Command $detectCommand -WorkingDirectory $resolvedProject -TimeoutSeconds 30
    $cpolar = ConvertFrom-WebDemoJsonText -Text $detectStep.stdout

    $cpolarUrl = $null
    if ([string]::IsNullOrWhiteSpace($PublicUrl)) {
        $getUrlScript = Join-Path $PSScriptRoot "get-cpolar-url.ps1"
        $getUrlCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value $getUrlScript) -Port $Port"
        $getUrlStep = Invoke-WebDemoCommand -Command $getUrlCommand -WorkingDirectory $resolvedProject -TimeoutSeconds 30
        $cpolarUrl = ConvertFrom-WebDemoJsonText -Text $getUrlStep.stdout
        if ($cpolarUrl -and $cpolarUrl.url) { $PublicUrl = [string]$cpolarUrl.url }
    }

    $publicValidation = $null
    if (-not [string]::IsNullOrWhiteSpace($PublicUrl)) {
        $publicValidation = Test-WebDemoHttpUrl -Url $PublicUrl -TimeoutSeconds 15
    }

    $findings = New-Object System.Collections.Generic.List[string]
    $nextActions = New-Object System.Collections.Generic.List[string]
    if ($pids.Count -eq 0) { $findings.Add("端口 $Port 没有监听进程。") | Out-Null }
    if ($runtimeState -and $runtimeState.port -eq $Port) { $findings.Add("runtime 状态记录的 PID 是 $($runtimeState.pid)。") | Out-Null }
    if (-not $localValidation.ok) {
        $findings.Add("localhost:$Port 不可访问。") | Out-Null
        $nextActions.Add("重新运行 publish.ps1，或检查 runtime.local.json 中的 PID 是否仍在运行。") | Out-Null
    }
    if ($null -ne $publicValidation -and -not $publicValidation.ok) {
        if ($publicValidation.statusCode -eq 502) {
            $findings.Add("公网返回 502，通常是本地端口未启动或隧道未指向 $Port。") | Out-Null
            $nextActions.Add("打开 http://localhost:9200/，确认 cpolar 隧道 addr 是否为 $Port。") | Out-Null
        }
        elseif ($publicValidation.statusCode -eq 403) {
            $findings.Add("公网返回 403，建议使用构建后的 vite preview，避免 dev server Host 限制。") | Out-Null
            $nextActions.Add("使用 publish.ps1 默认构建预览，避免 npm run dev。") | Out-Null
        }
        else {
            $findings.Add("公网验证失败：$($publicValidation.error)") | Out-Null
            $nextActions.Add("重新读取 cpolar URL；免费版域名可能已变化。") | Out-Null
        }
    }
    if ($cpolar -and -not $cpolar.available) {
        $findings.Add("未检测到可用 cpolar。") | Out-Null
        $nextActions.Add("如需外网访问，先安装或启动 cpolar；只本地预览可忽略。") | Out-Null
    }
    if ($findings.Count -eq 0) { $findings.Add("本地与已知公网检查未发现明显问题。") | Out-Null }
    if ($nextActions.Count -eq 0) { $nextActions.Add("无需额外处理；如外网域名变化，重新运行 get-cpolar-url.ps1。") | Out-Null }

    Write-WebDemoJson @{
        ok = $true
        projectPath = $resolvedProject
        port = $Port
        listeningPids = @($pids)
        localUrl = $localUrl
        local = $localValidation
        runtimeState = $runtimeState
        cpolar = $cpolar
        cpolarUrl = $cpolarUrl
        publicUrl = $PublicUrl
        public = $publicValidation
        findings = @($findings.ToArray())
        nextActions = @($nextActions.ToArray())
        message = "诊断完成"
    }
}
catch {
    Write-WebDemoJson @{ ok = $false; error = "diagnose_failed"; message = $_.Exception.Message; port = $Port } 1
}
