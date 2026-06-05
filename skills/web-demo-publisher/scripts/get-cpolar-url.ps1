param(
    [int]$Port = 9999,
    [string]$LogRoot,
    [switch]$OnlyLogRoot,
    [switch]$SkipPanel
)

. "$PSScriptRoot\common.ps1"

function Select-CpolarUrlCandidate {
    param(
        [Parameter(Mandatory = $true)][array]$Candidates
    )

    return @($Candidates | Sort-Object @{ Expression = "portHint"; Descending = $true }, @{ Expression = "isHttps"; Descending = $true }, @{ Expression = "lastWriteTime"; Descending = $true } | Select-Object -First 1)
}

function Find-CpolarUrlsInText {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][int]$Port,
        [string]$Source,
        [datetime]$LastWriteTime = (Get-Date)
    )

    $safeText = Remove-WebDemoSensitiveText -Text $Text
    $result = New-Object System.Collections.Generic.List[object]
    $urlMatches = [regex]::Matches($safeText, "https?://[A-Za-z0-9.-]+\.cpolar\.(top|cn|com)(:[0-9]+)?")
    if ($urlMatches.Count -eq 0) { return @() }
    $portHint = ($safeText -match "localhost:$Port" -or $safeText -match "127\.0\.0\.1:$Port" -or $safeText -match "addr[`"'=:\s]+$Port")
    foreach ($match in $urlMatches) {
        $url = $match.Value.TrimEnd('/', '.', ',', ';', '"', "'")
        $candidate = [pscustomobject]@{ url = $url; isHttps = $url.StartsWith("https://"); portHint = $portHint; source = $Source; lastWriteTime = $LastWriteTime }
        $result.Add($candidate) | Out-Null
    }
    return @($result.ToArray())
}

try {
    $candidates = New-Object System.Collections.Generic.List[object]

    if (-not $SkipPanel) {
        foreach ($panelUrl in @("http://localhost:9200/", "http://127.0.0.1:9200/")) {
            try {
                $panel = Invoke-WebRequest -Uri $panelUrl -UseBasicParsing -TimeoutSec 5
                foreach ($candidate in (Find-CpolarUrlsInText -Text ([string]$panel.Content) -Port $Port -Source "cpolar_panel")) {
                    $candidates.Add([object]$candidate) | Out-Null
                }
            }
            catch { }
        }
    }

    if ($OnlyLogRoot) {
        $logDirs = @($LogRoot) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) }
    }
    else {
        $logDirs = @(
            $LogRoot,
            $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE ".cpolar" }),
            $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE ".cpolar\logs" }),
            $(if ($env:ProgramData) { Join-Path $env:ProgramData "cpolar" }),
            $(if ($env:ProgramData) { Join-Path $env:ProgramData "cpolar\logs" })
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path -LiteralPath $_ -PathType Container) }
    }

    $files = @()
    foreach ($dir in $logDirs) {
        $files += @(Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match "(?i)\.(log|txt)$" } | Sort-Object LastWriteTime -Descending | Select-Object -First 10)
    }

    foreach ($file in ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 20)) {
        try { $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8) } catch { continue }
        foreach ($candidate in (Find-CpolarUrlsInText -Text $text -Port $Port -Source "cpolar_log" -LastWriteTime $file.LastWriteTime)) {
            $candidates.Add([object]$candidate) | Out-Null
        }
    }

    $best = @(Select-CpolarUrlCandidate -Candidates @($candidates.ToArray()))
    if ($best.Count -eq 0) {
        Write-WebDemoJson @{ ok = $false; found = $false; port = $Port; url = $null; source = $null; message = "未从 cpolar 面板或日志中找到公网地址，可打开 http://localhost:9200/ 查看" } 1
    }

    Write-WebDemoJson @{
        ok = $true
        found = $true
        port = $Port
        url = $best[0].url
        source = $best[0].source
        portHint = $best[0].portHint
        message = "已提取 cpolar 公网地址"
    }
}
catch {
    Write-WebDemoJson @{ ok = $false; error = "get_cpolar_url_failed"; message = $_.Exception.Message; port = $Port } 1
}
