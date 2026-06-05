param(
    [string]$ProjectPath = ".",
    [string]$ProjectType = "unknown",
    [string]$StaticRoot,
    [string]$PackageManager = "npm",
    [int]$Port = 9999,
    [switch]$UseStaticServer
)

. "$PSScriptRoot\common.ps1"

try {
    $resolvedProject = Resolve-WebDemoPath -Path $ProjectPath
    $mode = "static-server"
    $command = $null

    if ((@("slidev", "vite") -contains $ProjectType) -and -not $UseStaticServer) {
        $mode = "vite-preview"
        $command = Get-WebDemoVitePreviewCommand -PackageManager $PackageManager -Port $Port
        $workingDirectory = $resolvedProject
    }
    else {
        if ([string]::IsNullOrWhiteSpace($StaticRoot)) {
            if (Test-Path -LiteralPath (Join-Path $resolvedProject "dist\index.html") -PathType Leaf) {
                $StaticRoot = Join-Path $resolvedProject "dist"
            }
            else {
                $StaticRoot = $resolvedProject
            }
        }
        $resolvedStaticRoot = Resolve-WebDemoPath -Path $StaticRoot
        $serverScript = Join-Path $PSScriptRoot "start-static-server.ps1"
        $command = "& $(ConvertTo-WebDemoPowerShellLiteral -Value $serverScript) -Root $(ConvertTo-WebDemoPowerShellLiteral -Value $resolvedStaticRoot) -Port $Port"
        $workingDirectory = $resolvedStaticRoot
    }

    $process = Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command) -WorkingDirectory $workingDirectory -PassThru -WindowStyle Hidden
    Start-Sleep -Milliseconds 1200

    $localUrl = "http://localhost:$Port/"
    $validation = Test-WebDemoHttpUrl -Url $localUrl -TimeoutSeconds 10
    $statePath = $null
    if ($validation.ok) {
        $statePath = Write-WebDemoRuntimeState -State @{
            port = $Port
            pid = $process.Id
            projectPath = $resolvedProject
            command = $command
            mode = $mode
            localUrl = $localUrl
            startedAt = (Get-Date).ToString("o")
        }
    }
    $exitCode = if ($validation.ok) { 0 } else { 1 }
    Write-WebDemoJson @{
        ok = [bool]$validation.ok
        mode = $mode
        command = $command
        projectPath = $resolvedProject
        port = $Port
        pid = $process.Id
        localUrl = $localUrl
        validation = $validation
        runtimeStatePath = $statePath
        stopCommand = Get-WebDemoStopCommand -Port $Port
        message = if ($validation.ok) { "本地预览已启动" } else { "本地预览进程已启动，但 HTTP 验证未通过" }
    } $exitCode
}
catch {
    Write-WebDemoJson @{ ok = $false; error = "start_preview_failed"; message = $_.Exception.Message; port = $Port } 1
}
