param(
    [int]$Port = 9999
)

. "$PSScriptRoot\common.ps1"

try {
    $command = Get-Command cpolar -ErrorAction SilentlyContinue
    $service = Get-Service -Name cpolar -ErrorAction SilentlyContinue
    $panel = Test-WebDemoHttpUrl -Url "http://localhost:9200/" -TimeoutSeconds 5
    $configCandidates = @(
        (Join-Path $env:USERPROFILE ".cpolar\cpolar.yml"),
        (Join-Path $env:USERPROFILE ".cpolar\cpolar.yaml"),
        (Join-Path $env:ProgramData "cpolar\cpolar.yml"),
        (Join-Path $env:ProgramData "cpolar\cpolar.yaml")
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $configs = New-Object System.Collections.Generic.List[object]
    foreach ($path in $configCandidates) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
            $configs.Add(@{
                path = $path
                hasPublic9999 = ($text -match "public-9999")
                hasTargetPort = ($text -match "addr:\s*[`"']?$Port[`"']?")
            }) | Out-Null
        }
    }

    $available = ($null -ne $command) -or ($null -ne $service) -or $panel.ok -or ($configs.Count -gt 0)
    Write-WebDemoJson @{
        ok = $true
        available = $available
        commandPath = if ($command) { $command.Source } else { $null }
        service = if ($service) { @{ name = $service.Name; status = [string]$service.Status } } else { $null }
        panel = $panel
        configs = @($configs.ToArray())
        port = $Port
        message = if ($available) { "检测到 cpolar 相关配置或服务" } else { "未检测到可用 cpolar" }
    }
}
catch {
    Write-WebDemoJson @{ ok = $false; error = "detect_cpolar_failed"; message = $_.Exception.Message; port = $Port } 1
}
