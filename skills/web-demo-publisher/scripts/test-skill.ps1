param(
    [int]$Port = 19878
)

. "$PSScriptRoot\common.ps1"

function Add-TestResult {
    param(
        [System.Collections.Generic.List[object]]$Results,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Ok,
        [string]$Message = ""
    )
    $Results.Add(@{ name = $Name; ok = $Ok; message = $Message }) | Out-Null
}

function ConvertFrom-TestJson {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    try { return $Text | ConvertFrom-Json } catch { return $null }
}

$results = New-Object System.Collections.Generic.List[object]
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("web-demo-publisher-test-" + [System.Guid]::NewGuid().ToString("N"))
$logRoot = Join-Path $tempRoot "logs"
$projectRoot = Join-Path $tempRoot "project"

try {
    $parseErrors = @()
    foreach ($file in (Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.ps1)) {
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
        foreach ($error in $errors) { $parseErrors += "$($file.Name):$($error.Extent.StartLineNumber) $($error.Message)" }
    }
    Add-TestResult -Results $results -Name "parse_ps1" -Ok ($parseErrors.Count -eq 0) -Message ($parseErrors -join "; ")

    $templateRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "assets\templates"
    foreach ($template in @("landing-product", "slidev-talk", "tool-single-page")) {
        $metadata = Get-WebDemoTemplateMetadata -TemplateRoot (Join-Path $templateRoot $template)
        Add-TestResult -Results $results -Name "template_metadata_$template" -Ok ($null -ne $metadata -and $metadata.name -eq $template) -Message "metadata=$($metadata.name)"
    }

    New-Item -ItemType Directory -Path $tempRoot, $logRoot -Force | Out-Null
    $generateCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value (Join-Path $PSScriptRoot 'generate-from-template.ps1')) -Template tool-single-page -DestinationPath $(ConvertTo-WebDemoPowerShellLiteral -Value $projectRoot)"
    $generate = Invoke-WebDemoCommand -Command $generateCommand -WorkingDirectory $tempRoot -TimeoutSeconds 30
    $generateJson = ConvertFrom-TestJson -Text $generate.stdout
    Add-TestResult -Results $results -Name "generate_template" -Ok ([bool]$generateJson.ok -and (Test-Path -LiteralPath (Join-Path $projectRoot "index.html") -PathType Leaf)) -Message $generate.stderr

    $generateAgain = Invoke-WebDemoCommand -Command $generateCommand -WorkingDirectory $tempRoot -TimeoutSeconds 30
    $generateAgainJson = ConvertFrom-TestJson -Text $generateAgain.stdout
    Add-TestResult -Results $results -Name "generate_refuses_non_empty" -Ok ((-not [bool]$generateAgain["ok"]) -and $generateAgainJson.error -eq "destination_not_empty") -Message $generateAgain.stdout

    $detectCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value (Join-Path $PSScriptRoot 'detect-project.ps1')) -ProjectPath $(ConvertTo-WebDemoPowerShellLiteral -Value $projectRoot)"
    $detect = Invoke-WebDemoCommand -Command $detectCommand -WorkingDirectory $tempRoot -TimeoutSeconds 30
    $detectJson = ConvertFrom-TestJson -Text $detect.stdout
    Add-TestResult -Results $results -Name "detect_static_html" -Ok ([bool]$detectJson.ok -and $detectJson.type -eq "static-html") -Message $detect.stdout

    $designPath = Join-Path $projectRoot "DESIGN.md"
    @"
# Design System

## Brand
- Name: Demo Brand
- Tone: concise

## Colors
- Background: #ffffff
- Accent: #111111

## Typography
- Sans: Inter

## Visual Style
- Overall: quiet
- Avoid: heavy shadows
"@ | Set-Content -LiteralPath $designPath -Encoding UTF8
    $designCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value (Join-Path $PSScriptRoot 'detect-design-md.ps1')) -ProjectPath $(ConvertTo-WebDemoPowerShellLiteral -Value $projectRoot)"
    $design = Invoke-WebDemoCommand -Command $designCommand -WorkingDirectory $tempRoot -TimeoutSeconds 30
    $designJson = ConvertFrom-TestJson -Text $design.stdout
    Add-TestResult -Results $results -Name "detect_design_digest" -Ok ([bool]$designJson.ok -and [bool]$designJson.found -and $designJson.digest.colors.Background -eq "#ffffff") -Message $design.stdout

    $publishCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value (Join-Path $PSScriptRoot 'publish.ps1')) -ProjectPath $(ConvertTo-WebDemoPowerShellLiteral -Value $projectRoot) -Port $Port -UseCpolar off"
    $publish = Invoke-WebDemoCommand -Command $publishCommand -WorkingDirectory $tempRoot -TimeoutSeconds 60
    $publishJson = ConvertFrom-TestJson -Text $publish.stdout
    Add-TestResult -Results $results -Name "publish_static" -Ok ([bool]$publishJson.ok -and [bool]$publishJson.localOk) -Message $publish.stdout

    $stopCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value (Join-Path $PSScriptRoot 'stop-port.ps1')) -Port $Port"
    $stop = Invoke-WebDemoCommand -Command $stopCommand -WorkingDirectory $tempRoot -TimeoutSeconds 30
    $stopJson = ConvertFrom-TestJson -Text $stop.stdout
    Add-TestResult -Results $results -Name "stop_static" -Ok ([bool]$stopJson.ok) -Message $stop.stdout

    $logText = 'RespStartTunnel LocalAddr=http://localhost:' + $Port + ' Url=https://abc123.cpolar.top authtoken=secret-token'
    Set-Content -LiteralPath (Join-Path $logRoot "cpolar.log") -Value $logText -Encoding UTF8
    $cpolarCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value (Join-Path $PSScriptRoot 'get-cpolar-url.ps1')) -Port $Port -LogRoot $(ConvertTo-WebDemoPowerShellLiteral -Value $logRoot) -OnlyLogRoot -SkipPanel"
    $cpolar = Invoke-WebDemoCommand -Command $cpolarCommand -WorkingDirectory $tempRoot -TimeoutSeconds 30
    $cpolarJson = ConvertFrom-TestJson -Text $cpolar.stdout
    Add-TestResult -Results $results -Name "cpolar_log_extract" -Ok ([bool]$cpolarJson.ok -and $cpolarJson.url -eq "https://abc123.cpolar.top" -and $cpolar.stdout -notmatch "secret-token") -Message $cpolar.stdout
}
finally {
    try {
        $cleanupStopCommand = "& $(ConvertTo-WebDemoPowerShellLiteral -Value (Join-Path $PSScriptRoot 'stop-port.ps1')) -Port $Port"
        Invoke-WebDemoCommand -Command $cleanupStopCommand -WorkingDirectory ([System.IO.Path]::GetTempPath()) -TimeoutSeconds 30 | Out-Null
    }
    catch { }
    if (Test-Path -LiteralPath $tempRoot) {
        $resolvedTemp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        $resolvedTarget = [System.IO.Path]::GetFullPath($tempRoot)
        if ($resolvedTarget.StartsWith($resolvedTemp, [System.StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$failed = @($results.ToArray() | Where-Object { -not $_.ok })
$exitCode = if ($failed.Count -eq 0) { 0 } else { 1 }
Write-WebDemoJson @{ ok = ($failed.Count -eq 0); tests = @($results.ToArray()); failed = @($failed); message = if ($failed.Count -eq 0) { "web-demo-publisher 自测通过" } else { "web-demo-publisher 自测失败" } } $exitCode
