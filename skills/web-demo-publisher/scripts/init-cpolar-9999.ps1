param(
    [string]$ConfigPath,
    [switch]$WriteConfig
)

. "$PSScriptRoot\common.ps1"

try {
    $snippet = @"
tunnels:
  public-9999:
    proto: http
    addr: "9999"
    bind_tls: both
    start_type: enable
"@

    if (-not $WriteConfig) {
        Write-WebDemoJson @{
            ok = $true
            wrote = $false
            snippet = $snippet
            message = "未修改 cpolar 配置。需要写入时请在用户确认后使用 -WriteConfig。"
            nextAction = "确认不会覆盖现有隧道后，将片段加入 cpolar.yml，并重启 cpolar 服务或隧道。"
        }
    }

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Join-Path $env:USERPROFILE ".cpolar\cpolar.yml"
    }
    $parent = Split-Path -Parent $ConfigPath
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $backupPath = $null
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        $backupPath = "$ConfigPath.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item -LiteralPath $ConfigPath -Destination $backupPath
        $existing = [System.IO.File]::ReadAllText($ConfigPath, [System.Text.Encoding]::UTF8)
        if ($existing -match "public-9999") {
            Write-WebDemoJson @{ ok = $true; wrote = $false; configPath = $ConfigPath; backupPath = $backupPath; message = "配置中已存在 public-9999，未重复写入。" }
        }
        Add-Content -LiteralPath $ConfigPath -Value "`n$snippet" -Encoding UTF8
    }
    else {
        Set-Content -LiteralPath $ConfigPath -Value $snippet -Encoding UTF8
    }

    Write-WebDemoJson @{ ok = $true; wrote = $true; configPath = $ConfigPath; backupPath = $backupPath; message = "已写入 public-9999 隧道配置；未写入任何 authtoken。" }
}
catch {
    Write-WebDemoJson @{ ok = $false; error = "init_cpolar_failed"; message = $_.Exception.Message } 1
}

