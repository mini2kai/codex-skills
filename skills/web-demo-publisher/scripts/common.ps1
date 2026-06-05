Set-StrictMode -Version Latest

function Write-WebDemoJson {
    param(
        [Parameter(Mandatory = $true)]$Payload,
        [int]$ExitCode = 0
    )

    $Payload | ConvertTo-Json -Depth 12
    exit $ExitCode
}

function Remove-WebDemoSensitiveText {
    param([AllowNull()][string]$Text)

    if ($null -eq $Text) { return $null }
    $clean = $Text
    $clean = [regex]::Replace($clean, '(?i)(authtoken\s*[:=]\s*)\S+', '$1[REDACTED]')
    $clean = [regex]::Replace($clean, '(?i)(token\s*[:=]\s*)\S+', '$1[REDACTED]')
    $clean = [regex]::Replace($clean, '(?i)(password\s*[:=]\s*)\S+', '$1[REDACTED]')
    $clean = [regex]::Replace($clean, '(?i)(passwd\s*[:=]\s*)\S+', '$1[REDACTED]')
    $clean = [regex]::Replace($clean, '(?i)(Authorization:\s*Bearer\s+)\S+', '$1[REDACTED]')
    return $clean
}

function ConvertTo-WebDemoPowerShellLiteral {
    param([Parameter(Mandatory = $true)][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Resolve-WebDemoPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "路径不存在：$Path"
    }

    return (Resolve-Path -LiteralPath $Path).ProviderPath
}

function Get-WebDemoPackageData {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)

    $packagePath = Join-Path $ProjectPath "package.json"
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) {
        return $null
    }

    try {
        return [System.IO.File]::ReadAllText($packagePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    }
    catch {
        throw "package.json 解析失败：$($_.Exception.Message)"
    }
}

function Get-WebDemoPackageManager {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)

    if (Test-Path -LiteralPath (Join-Path $ProjectPath "pnpm-lock.yaml") -PathType Leaf) { return "pnpm" }
    if (Test-Path -LiteralPath (Join-Path $ProjectPath "yarn.lock") -PathType Leaf) { return "yarn" }
    if (Test-Path -LiteralPath (Join-Path $ProjectPath "package-lock.json") -PathType Leaf) { return "npm" }
    return "npm"
}

function Get-WebDemoPackageScripts {
    param([Parameter(Mandatory = $true)]$Package)

    $scripts = @{}
    if ($null -ne $Package -and $Package.PSObject.Properties["scripts"]) {
        foreach ($property in $Package.scripts.PSObject.Properties) { $scripts[$property.Name] = [string]$property.Value }
    }
    return $scripts
}

function Get-WebDemoScriptCommand {
    param(
        [Parameter(Mandatory = $true)][string]$PackageManager,
        [Parameter(Mandatory = $true)][string]$ScriptName
    )

    switch ($PackageManager) {
        "pnpm" { return "pnpm run $ScriptName" }
        "yarn" { return "yarn $ScriptName" }
        default { return "npm run $ScriptName" }
    }
}

function Get-WebDemoInstallCommand {
    param([Parameter(Mandatory = $true)][string]$PackageManager)

    switch ($PackageManager) {
        "pnpm" { return "pnpm install" }
        "yarn" { return "yarn install" }
        default { return "npm install" }
    }
}

function Get-WebDemoBuildCommand {
    param([Parameter(Mandatory = $true)][string]$PackageManager)

    switch ($PackageManager) {
        "pnpm" { return "pnpm run build" }
        "yarn" { return "yarn build" }
        default { return "npm run build" }
    }
}

function Get-WebDemoVitePreviewCommand {
    param(
        [Parameter(Mandatory = $true)][string]$PackageManager,
        [Parameter(Mandatory = $true)][int]$Port,
        $Scripts = @{}
    )

    if ($Scripts.ContainsKey("preview")) {
        return (Get-WebDemoScriptCommand -PackageManager $PackageManager -ScriptName "preview") + " -- --host 127.0.0.1 --port $Port"
    }

    switch ($PackageManager) {
        "pnpm" { return "pnpm exec vite preview --host 127.0.0.1 --port $Port" }
        "yarn" { return "npx vite preview --host 127.0.0.1 --port $Port" }
        default { return "npx vite preview --host 127.0.0.1 --port $Port" }
    }
}

function Invoke-WebDemoCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [int]$TimeoutSeconds = 600
    )

    $stdoutPath = Join-Path ([System.IO.Path]::GetTempPath()) ("web-demo-stdout-" + [System.Guid]::NewGuid().ToString("N") + ".log")
    $stderrPath = Join-Path ([System.IO.Path]::GetTempPath()) ("web-demo-stderr-" + [System.Guid]::NewGuid().ToString("N") + ".log")

    $process = Start-Process -FilePath "powershell.exe" `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $Command) `
        -WorkingDirectory $WorkingDirectory `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru `
        -WindowStyle Hidden

    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    if (-not $completed) {
        try { $process.Kill($true) } catch { }
    }

    $stdout = if (Test-Path -LiteralPath $stdoutPath) { Remove-WebDemoSensitiveText -Text ([System.IO.File]::ReadAllText($stdoutPath, [System.Text.Encoding]::UTF8).Trim()) } else { "" }
    $stderr = if (Test-Path -LiteralPath $stderrPath) { Remove-WebDemoSensitiveText -Text ([System.IO.File]::ReadAllText($stderrPath, [System.Text.Encoding]::UTF8).Trim()) } else { "" }
    Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

    if (-not $completed) {
        return @{ ok = $false; command = $Command; exitCode = $null; timedOut = $true; stdout = $stdout; stderr = "命令超时" }
    }

    return @{ ok = ($process.ExitCode -eq 0); command = $Command; exitCode = $process.ExitCode; timedOut = $false; stdout = $stdout; stderr = $stderr }
}

function Get-WebDemoProjectInfo {
    param([Parameter(Mandatory = $true)][string]$ProjectPath)

    $resolved = Resolve-WebDemoPath -Path $ProjectPath
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "ProjectPath 不是目录：$resolved"
    }

    $package = Get-WebDemoPackageData -ProjectPath $resolved
    $signals = New-Object System.Collections.Generic.List[string]
    $type = "unknown"
    $staticRoot = $null
    $packageManager = Get-WebDemoPackageManager -ProjectPath $resolved
    $hasSlides = Test-Path -LiteralPath (Join-Path $resolved "slides.md") -PathType Leaf
    $hasDistIndex = Test-Path -LiteralPath (Join-Path $resolved "dist\index.html") -PathType Leaf
    $hasRootIndex = Test-Path -LiteralPath (Join-Path $resolved "index.html") -PathType Leaf

    if ($hasSlides) { $signals.Add("slides.md") | Out-Null }
    if ($hasDistIndex) { $signals.Add("dist/index.html") | Out-Null }
    if ($hasRootIndex) { $signals.Add("index.html") | Out-Null }

    $scripts = @{}
    $dependenciesText = ""
    if ($null -ne $package) {
        $scripts = Get-WebDemoPackageScripts -Package $package
        foreach ($propertyName in @("dependencies", "devDependencies")) {
            if ($package.PSObject.Properties[$propertyName]) {
                $dependenciesText += " " + (($package.$propertyName.PSObject.Properties | ForEach-Object { $_.Name }) -join " ")
            }
        }
    }

    if ($hasSlides -or $dependenciesText -match "@slidev/cli" -or ($scripts.Values -join " ") -match "slidev") {
        $type = "slidev"
        $signals.Add("slidev") | Out-Null
    }
    elseif ($dependenciesText -match "(^|\s)vite(\s|$)" -or $scripts.ContainsKey("build")) {
        $type = "vite"
        $signals.Add("vite_or_build_script") | Out-Null
    }
    elseif ($hasDistIndex) {
        $type = "static-dist"
        $staticRoot = Join-Path $resolved "dist"
    }
    elseif ($hasRootIndex) {
        $type = "static-html"
        $staticRoot = $resolved
    }

    return @{
        ok = $true
        projectPath = $resolved
        type = $type
        packageManager = $packageManager
        hasPackageJson = ($null -ne $package)
        hasNodeModules = (Test-Path -LiteralPath (Join-Path $resolved "node_modules") -PathType Container)
        hasBuildScript = ($scripts.ContainsKey("build"))
        hasPreviewScript = ($scripts.ContainsKey("preview"))
        scripts = $scripts
        requiresBuild = (@("slidev", "vite") -contains $type)
        staticRoot = $staticRoot
        signals = @($signals.ToArray())
    }
}

function Get-WebDemoSkillRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Get-WebDemoRuntimeStatePath {
    $dataDir = Join-Path (Get-WebDemoSkillRoot) "data"
    if (-not (Test-Path -LiteralPath $dataDir -PathType Container)) {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    }
    return (Join-Path $dataDir "runtime.local.json")
}

function Read-WebDemoRuntimeState {
    $path = Get-WebDemoRuntimeStatePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    try { return [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) | ConvertFrom-Json } catch { return $null }
}

function Write-WebDemoRuntimeState {
    param([Parameter(Mandatory = $true)]$State)

    $path = Get-WebDemoRuntimeStatePath
    ($State | ConvertTo-Json -Depth 12) | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Clear-WebDemoRuntimeState {
    $path = Get-WebDemoRuntimeStatePath
    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
}

function Get-WebDemoTemplateMetadata {
    param([Parameter(Mandatory = $true)][string]$TemplateRoot)

    $metadataPath = Join-Path $TemplateRoot "template.json"
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { return $null }
    return [System.IO.File]::ReadAllText($metadataPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
}

function Get-WebDemoDesignDigest {
    param([Parameter(Mandatory = $true)][string]$DesignPath)

    $text = [System.IO.File]::ReadAllText($DesignPath, [System.Text.Encoding]::UTF8)
    $digest = [ordered]@{
        brand = @{}
        colors = @{}
        typography = @{}
        visualStyle = @()
        avoid = @()
        layout = @()
        contentRules = @()
        rawSummary = (($text -replace "\s+", " ").Trim())
    }
    if ($digest["rawSummary"].Length -gt 600) { $digest["rawSummary"] = $digest["rawSummary"].Substring(0, 600) + "..." }

    $section = ""
    foreach ($line in ($text -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^##\s+(.+)$') { $section = $Matches[1].Trim().ToLowerInvariant(); continue }
        if ($trimmed -notmatch '^[-*]\s*(.+)$') { continue }
        $item = $Matches[1].Trim()
        $key = $null
        $value = $item
        if ($item -match '^([^:：]+)[:：]\s*(.+)$') { $key = $Matches[1].Trim(); $value = $Matches[2].Trim() }

        switch -Regex ($section) {
            'brand' { if ($key) { $digest["brand"][$key] = $value } else { $digest["brand"][$item] = $true } }
            'colors?' { if ($key) { $digest["colors"][$key] = $value } }
            'typography' { if ($key) { $digest["typography"][$key] = $value } }
            'visual|style' {
                if ($key -and $key -match '(?i)^avoid$') { $digest["avoid"] += $value } else { $digest["visualStyle"] += $item }
            }
            'layout' { $digest["layout"] += $item }
            'content|copy' { $digest["contentRules"] += $item }
        }
    }

    return $digest
}

function Test-WebDemoHttpUrl {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [int]$TimeoutSeconds = 10
    )

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSeconds -MaximumRedirection 3
        return @{ ok = ($response.StatusCode -ge 200 -and $response.StatusCode -lt 400); statusCode = [int]$response.StatusCode; error = $null }
    }
    catch {
        $status = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        return @{ ok = $false; statusCode = $status; error = $_.Exception.Message }
    }
}

function Get-WebDemoStopCommand {
    param([Parameter(Mandatory = $true)][int]$Port)

    return "Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id `$_.OwningProcess -ErrorAction SilentlyContinue }"
}
