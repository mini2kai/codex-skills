param(
    [string]$ProjectPath = "."
)

. "$PSScriptRoot\common.ps1"

try {
    $info = Get-WebDemoProjectInfo -ProjectPath $ProjectPath
    Write-WebDemoJson @{
        ok = $true
        projectPath = $info.projectPath
        type = $info.type
        packageManager = $info.packageManager
        hasPackageJson = $info.hasPackageJson
        hasNodeModules = $info.hasNodeModules
        hasBuildScript = $info.hasBuildScript
        requiresBuild = $info.requiresBuild
        staticRoot = $info.staticRoot
        signals = $info.signals
        message = "项目识别完成：$($info.type)"
    }
}
catch {
    Write-WebDemoJson @{ ok = $false; error = "detect_failed"; message = $_.Exception.Message } 1
}
