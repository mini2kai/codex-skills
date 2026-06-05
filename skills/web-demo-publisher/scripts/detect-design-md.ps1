param(
    [string]$ProjectPath = ".",
    [string]$DesignPath
)

. "$PSScriptRoot\common.ps1"

try {
    $resolvedProject = Resolve-WebDemoPath -Path $ProjectPath
    $candidates = New-Object System.Collections.Generic.List[string]

    if (-not [string]::IsNullOrWhiteSpace($DesignPath)) {
        $candidates.Add($DesignPath) | Out-Null
    }
    $candidates.Add((Join-Path $resolvedProject "DESIGN.md")) | Out-Null
    $parent = Split-Path -Parent $resolvedProject
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $candidates.Add((Join-Path $parent "DESIGN.md")) | Out-Null
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $path = (Resolve-Path -LiteralPath $candidate).ProviderPath
            $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
            $summary = ($text -replace "\s+", " ").Trim()
            if ($summary.Length -gt 600) { $summary = $summary.Substring(0, 600) + "..." }
            $digest = Get-WebDemoDesignDigest -DesignPath $path
            Write-WebDemoJson @{ ok = $true; found = $true; path = $path; summary = $summary; digest = $digest; message = "已找到 DESIGN.md" }
        }
    }

    Write-WebDemoJson @{ ok = $true; found = $false; path = $null; summary = $null; message = "未找到 DESIGN.md，使用默认设计规则" }
}
catch {
    Write-WebDemoJson @{ ok = $false; error = "detect_design_failed"; message = $_.Exception.Message } 1
}
