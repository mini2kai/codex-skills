param(
    [Parameter(Mandatory = $true)][string]$Template,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [switch]$Force
)

. "$PSScriptRoot\common.ps1"

try {
    $templateRoot = Join-Path (Split-Path -Parent $PSScriptRoot) "assets\templates\$Template"
    if (-not (Test-Path -LiteralPath $templateRoot -PathType Container)) {
        Write-WebDemoJson @{ ok = $false; error = "missing_template"; template = $Template; message = "未找到模板：$Template" } 1
    }
    $metadata = Get-WebDemoTemplateMetadata -TemplateRoot $templateRoot

    $destinationFull = [System.IO.Path]::GetFullPath($DestinationPath)
    if ((Test-Path -LiteralPath $destinationFull -PathType Container) -and -not $Force) {
        $existing = @(Get-ChildItem -LiteralPath $destinationFull -Force | Select-Object -First 1)
        if ($existing.Count -gt 0) {
            Write-WebDemoJson @{ ok = $false; error = "destination_not_empty"; destinationPath = $destinationFull; message = "目标目录非空，避免覆盖。确认后可使用 -Force。" } 1
        }
    }

    New-Item -ItemType Directory -Path $destinationFull -Force | Out-Null
    Get-ChildItem -LiteralPath $templateRoot -Force | Where-Object { $_.Name -ne "template.json" } | Copy-Item -Destination $destinationFull -Recurse -Force
    Write-WebDemoJson @{ ok = $true; template = $Template; metadata = $metadata; destinationPath = $destinationFull; message = "已从模板生成项目" }
}
catch {
    Write-WebDemoJson @{ ok = $false; error = "generate_template_failed"; template = $Template; message = $_.Exception.Message } 1
}
