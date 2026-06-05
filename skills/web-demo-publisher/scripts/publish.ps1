param(
    [string]$ProjectPath = ".",
    [int]$Port = 9999,
    [ValidateSet("auto", "required", "off")][string]$UseCpolar = "auto",
    [string]$NodeVersion,
    [switch]$SkipInstall,
    [switch]$SkipBuild,
    [switch]$UseStaticServer
)

. "$PSScriptRoot\common.ps1"

function Add-Step {
    param(
        [System.Collections.Generic.List[object]]$Steps,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)]$Result
    )
    $Steps.Add(@{ name = $Name; result = $Result }) | Out-Null
}

function ConvertFrom-WebDemoJsonText {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { return $Text | ConvertFrom-Json } catch { return $null }
}

function Start-WebDemoPreviewProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    return Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $Command) -WorkingDirectory $WorkingDirectory -PassThru -WindowStyle Hidden
}

try {
    $steps = New-Object System.Collections.Generic.List[object]
    $info = Get-WebDemoProjectInfo -ProjectPath $ProjectPath
    Add-Step -Steps $steps -Name "detect_project" -Result $info

    if ($info.type -eq "unknown") {
        Write-WebDemoJson @{
            ok = $false
            localOk = $false
            publicOk = $false
            error = "unknown_project"
            project = $info
            steps = @($steps.ToArray())
            message = "无法识别项目类型。请确认存在 slides.md、package.json、dist/index.html 或 index.html。"
        } 1
    }

    if (-not [string]::IsNullOrWhiteSpace($NodeVersion)) {
        $nvm = Get-Command nvm -ErrorAction SilentlyContinue
        if ($nvm) {
            $nodeStep = Invoke-WebDemoCommand -Command "nvm use $NodeVersion" -WorkingDirectory $info.projectPath -TimeoutSeconds 120
            Add-Step -Steps $steps -Name "node_version" -Result $nodeStep
        }
        else {
            Add-Step -Steps $steps -Name "node_version" -Result @{ ok = $true; skipped = $true; message = "未检测到 nvm，跳过 Node 版本切换" }
        }
    }

    if ($info.requiresBuild) {
        if (-not $info.hasPackageJson) {
            Write-WebDemoJson @{ ok = $false; localOk = $false; publicOk = $false; project = $info; steps = @($steps.ToArray()); message = "项目需要构建，但缺少 package.json。" } 1
        }

        if (-not $info.hasNodeModules -and -not $SkipInstall) {
            $installCommand = Get-WebDemoInstallCommand -PackageManager $info.packageManager
            $installStep = Invoke-WebDemoCommand -Command $installCommand -WorkingDirectory $info.projectPath -TimeoutSeconds 900
            Add-Step -Steps $steps -Name "install_dependencies" -Result $installStep
            if (-not $installStep.ok) {
                Write-WebDemoJson @{ ok = $false; localOk = $false; publicOk = $false; project = $info; steps = @($steps.ToArray()); message = "依赖安装失败。" } 1
            }
        }
        elseif ($SkipInstall) {
            Add-Step -Steps $steps -Name "install_dependencies" -Result @{ ok = $true; skipped = $true; message = "按参数跳过依赖安装" }
        }

        if (-not $SkipBuild) {
            if ($info.hasBuildScript) {
                $buildCommand = Get-WebDemoBuildCommand -PackageManager $info.packageManager
            }
            elseif ($info.type -eq "slidev") {
                $buildCommand = switch ($info.packageManager) {
                    "pnpm" { "pnpm exec slidev build" }
                    default { "npx slidev build" }
                }
            }
            else {
                $buildCommand = $null
            }

            if ($null -ne $buildCommand) {
                $buildStep = Invoke-WebDemoCommand -Command $buildCommand -WorkingDirectory $info.projectPath -TimeoutSeconds 900
                Add-Step -Steps $steps -Name "build" -Result $buildStep
                if (-not $buildStep.ok) {
                    Write-WebDemoJson @{ ok = $false; localOk = $false; publicOk = $false; project = $info; steps = @($steps.ToArray()); message = "项目构建失败。" } 1
                }
            }
            else {
                Add-Step -Steps $steps -Name "build" -Result @{ ok = $true; skipped = $true; message = "未找到构建命令，跳过构建" }
            }
        }
        else {
            Add-Step -Steps $steps -Name "build" -Result @{ ok = $true; skipped = $true; message = "按参数跳过构建" }
        }
    }

    $stopScript = Join-Path $PSScriptRoot "stop-port.ps1"
    $stopCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value $stopScript) -Port $Port"
    $stopStep = Invoke-WebDemoCommand -Command $stopCommand -WorkingDirectory $info.projectPath -TimeoutSeconds 30
    $stopJson = ConvertFrom-WebDemoJsonText -Text $stopStep.stdout
    $stopOk = [bool]$stopStep.ok
    if ($stopJson -and $stopJson.ok) { $stopOk = $true }
    Add-Step -Steps $steps -Name "stop_port" -Result @{ ok = $stopOk; parsed = $stopJson; stderr = $stopStep.stderr }

    $mode = "static-server"
    if ((@("slidev", "vite") -contains $info.type) -and -not $UseStaticServer) {
        $mode = "vite-preview"
        $previewCommand = Get-WebDemoVitePreviewCommand -PackageManager $info.packageManager -Port $Port -Scripts $info.scripts
        $workingDirectory = $info.projectPath
    }
    else {
        $staticRoot = $info.staticRoot
        if ([string]::IsNullOrWhiteSpace($staticRoot)) {
            if (Test-Path -LiteralPath (Join-Path $info.projectPath "dist\index.html") -PathType Leaf) { $staticRoot = Join-Path $info.projectPath "dist" }
            else { $staticRoot = $info.projectPath }
        }
        $serverScript = Join-Path $PSScriptRoot "start-static-server.ps1"
        $previewCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value $serverScript) -Root $(ConvertTo-WebDemoPowerShellLiteral -Value $staticRoot) -Port $Port"
        $workingDirectory = $staticRoot
    }

    $previewProcess = Start-WebDemoPreviewProcess -Command $previewCommand -WorkingDirectory $workingDirectory
    Start-Sleep -Milliseconds 1500
    $localUrl = "http://localhost:$Port/"
    $localValidation = Test-WebDemoHttpUrl -Url $localUrl -TimeoutSeconds 10
    Add-Step -Steps $steps -Name "local_preview" -Result @{ ok = $localValidation.ok; mode = $mode; pid = $previewProcess.Id; command = $previewCommand; validation = $localValidation }

    if (-not $localValidation.ok -and $mode -eq "vite-preview" -and (Test-Path -LiteralPath (Join-Path $info.projectPath "dist\index.html") -PathType Leaf)) {
        try { Stop-Process -Id $previewProcess.Id -ErrorAction SilentlyContinue } catch { }
        $mode = "static-server"
        $staticRoot = Join-Path $info.projectPath "dist"
        $serverScript = Join-Path $PSScriptRoot "start-static-server.ps1"
        $previewCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value $serverScript) -Root $(ConvertTo-WebDemoPowerShellLiteral -Value $staticRoot) -Port $Port"
        $workingDirectory = $staticRoot
        $previewProcess = Start-WebDemoPreviewProcess -Command $previewCommand -WorkingDirectory $workingDirectory
        Start-Sleep -Milliseconds 1000
        $localValidation = Test-WebDemoHttpUrl -Url $localUrl -TimeoutSeconds 10
        Add-Step -Steps $steps -Name "fallback_static_preview" -Result @{ ok = $localValidation.ok; mode = $mode; pid = $previewProcess.Id; command = $previewCommand; validation = $localValidation }
    }

    if ($localValidation.ok) {
        $statePath = Write-WebDemoRuntimeState -State @{
            port = $Port
            pid = $previewProcess.Id
            projectPath = $info.projectPath
            command = $previewCommand
            mode = $mode
            localUrl = $localUrl
            startedAt = (Get-Date).ToString("o")
        }
        Add-Step -Steps $steps -Name "write_runtime_state" -Result @{ ok = $true; path = $statePath }
    }
    else {
        try { Stop-Process -Id $previewProcess.Id -ErrorAction SilentlyContinue } catch { }
    }

    $publicResult = $null
    if ($UseCpolar -ne "off" -and $localValidation.ok) {
        $getUrlScript = Join-Path $PSScriptRoot "get-cpolar-url.ps1"
        $getUrlCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value $getUrlScript) -Port $Port"
        $getUrlStep = Invoke-WebDemoCommand -Command $getUrlCommand -WorkingDirectory $info.projectPath -TimeoutSeconds 30
        $getUrlJson = ConvertFrom-WebDemoJsonText -Text $getUrlStep.stdout
        Add-Step -Steps $steps -Name "get_cpolar_url" -Result @{ ok = $getUrlStep.ok; parsed = $getUrlJson; stderr = $getUrlStep.stderr }

        if ($getUrlStep.ok -and $null -ne $getUrlJson -and $getUrlJson.url) {
            $validateScript = Join-Path $PSScriptRoot "validate-public-url.ps1"
            $validateCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value $validateScript) -Url $(ConvertTo-WebDemoPowerShellLiteral -Value ([string]$getUrlJson.url))"
            $validateStep = Invoke-WebDemoCommand -Command $validateCommand -WorkingDirectory $info.projectPath -TimeoutSeconds 30
            $validateJson = ConvertFrom-WebDemoJsonText -Text $validateStep.stdout
            Add-Step -Steps $steps -Name "validate_public_url" -Result @{ ok = $validateStep.ok; parsed = $validateJson; stderr = $validateStep.stderr }
            $publicResult = $validateJson
        }
        else {
            $publicResult = @{ ok = $false; url = $null; reason = "未检测到可用 cpolar 公网地址" }
        }
    }
    elseif ($UseCpolar -eq "off") {
        Add-Step -Steps $steps -Name "cpolar" -Result @{ ok = $true; skipped = $true; message = "按参数跳过 cpolar" }
    }

    $localOk = [bool]$localValidation.ok
    $publicOk = ($null -ne $publicResult -and [bool]$publicResult.ok)
    $overallOk = $localOk -and (($UseCpolar -ne "required") -or $publicOk)
    $exitCode = if ($overallOk) { 0 } else { 1 }
    $nextAction = if (-not $localOk) {
        "查看 steps.local_preview.validation，确认服务命令、端口和构建产物。"
    }
    elseif ($UseCpolar -eq "off") {
        "只本地预览已完成；需要外网分享时重新使用 -UseCpolar auto。"
    }
    elseif ($publicOk) {
        "可以分享 publicUrl；免费版 cpolar 域名变化时重新运行发布脚本。"
    }
    else {
        "本地已可访问；公网暂不可用，请检查 cpolar 面板、隧道端口和公网验证原因。"
    }

    Write-WebDemoJson @{
        ok = $overallOk
        localOk = $localOk
        publicOk = $publicOk
        project = $info
        port = $Port
        localUrl = $localUrl
        publicUrl = if ($publicOk) { [string]$publicResult.url } else { $null }
        public = $publicResult
        pid = $previewProcess.Id
        mode = $mode
        stopCommand = Get-WebDemoStopCommand -Port $Port
        summary = @{
            localStatus = if ($localOk) { "success" } else { "failed" }
            publicStatus = if ($UseCpolar -eq "off") { "skipped" } elseif ($publicOk) { "success" } else { "failed" }
            nextAction = $nextAction
        }
        steps = @($steps.ToArray())
        message = if ($overallOk) { "发布流程完成" } elseif ($localOk) { "本地发布已完成；公网暂不可用" } else { "本地发布失败" }
    } $exitCode
}
catch {
    Write-WebDemoJson @{ ok = $false; localOk = $false; publicOk = $false; error = "publish_failed"; port = $Port; message = $_.Exception.Message } 1
}
