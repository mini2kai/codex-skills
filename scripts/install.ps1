Set-StrictMode -Version Latest

$script:CodexSkillsDefaultRepo = "mini2kai/codex-skills"
$script:CodexSkillsDefaultRef = "main"

function Get-CodexInstallerCommand {
    param(
        [string]$Repo = $script:CodexSkillsDefaultRepo,
        [string]$Ref = $script:CodexSkillsDefaultRef
    )

    return "irm https://raw.githubusercontent.com/$Repo/$Ref/scripts/install.ps1 | iex"
}

function Write-CodexSuggestion {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host $Message -ForegroundColor Cyan
}

function Test-CodexChildPath {
    param(
        [Parameter(Mandatory = $true)][string]$Parent,
        [Parameter(Mandatory = $true)][string]$Child
    )

    $parentFull = [System.IO.Path]::GetFullPath($Parent).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $childFull = [System.IO.Path]::GetFullPath($Child).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    return $childFull.Equals($parentFull, [System.StringComparison]::OrdinalIgnoreCase) -or
        $childFull.StartsWith($parentFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase) -or
        $childFull.StartsWith($parentFull + [System.IO.Path]::AltDirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-CodexSkillName {
    param([Parameter(Mandatory = $true)][string]$Name)

    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Skill 名称不合法：$Name。只能使用英文字母、数字、点、下划线和连字符。"
    }
}

function Get-CodexInstallRoot {
    return (Get-Location).ProviderPath
}

function Get-CodexLocalRepoRoot {
    if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $null
    }

    $candidate = Split-Path -Parent $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        return $null
    }

    $manifest = Join-Path $candidate "manifest.json"
    $skills = Join-Path $candidate "skills"
    if ((Test-Path -LiteralPath $manifest -PathType Leaf) -and (Test-Path -LiteralPath $skills -PathType Container)) {
        return $candidate
    }

    return $null
}

function Get-CodexArchiveUrlCandidates {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Ref
    )

    return @(
        "https://github.com/$Repo/archive/refs/heads/$Ref.zip",
        "https://github.com/$Repo/archive/refs/tags/$Ref.zip",
        "https://github.com/$Repo/archive/$Ref.zip"
    )
}

function Save-CodexRepoArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $errors = New-Object System.Collections.Generic.List[string]
    foreach ($url in (Get-CodexArchiveUrlCandidates -Repo $Repo -Ref $Ref)) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $Destination -UseBasicParsing -ErrorAction Stop
            if ((Test-Path -LiteralPath $Destination -PathType Leaf) -and ((Get-Item -LiteralPath $Destination).Length -gt 0)) {
                return $url
            }
        }
        catch {
            $errors.Add("$url -> $($_.Exception.Message)") | Out-Null
        }
    }

    throw "下载仓库失败：$Repo@$Ref。请检查网络、仓库地址、分支或 tag 是否存在。`n$($errors -join "`n")"
}

function Get-CodexRemoteRepoRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string]$WorkDir
    )

    $zipPath = Join-Path $WorkDir "repo.zip"
    $extractPath = Join-Path $WorkDir "repo"

    $url = Save-CodexRepoArchive -Repo $Repo -Ref $Ref -Destination $zipPath
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $children = @(Get-ChildItem -LiteralPath $extractPath -Directory)
    if ($children.Count -eq 0) {
        throw "下载的仓库压缩包无效：$url 中没有仓库目录。"
    }

    return $children[0].FullName
}

function Get-CodexSkillManifest {
    param([Parameter(Mandatory = $true)][string]$RepoRoot)

    $manifestPath = Join-Path $RepoRoot "manifest.json"
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        return $null
    }

    return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
}

function Show-CodexSkillList {
    [CmdletBinding()]
    param(
        [string]$Repo = $script:CodexSkillsDefaultRepo,
        [string]$Ref = $script:CodexSkillsDefaultRef
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-skills-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        $repoRoot = Get-CodexLocalRepoRoot
        if ($null -eq $repoRoot) {
            Write-Host "正在读取 skill 列表：$Repo@$Ref ..."
            $repoRoot = Get-CodexRemoteRepoRoot -Repo $Repo -Ref $Ref -WorkDir $tempRoot
        }

        $manifest = Get-CodexSkillManifest -RepoRoot $repoRoot
        Write-Host "可安装的 skill：" -ForegroundColor Green

        if ($null -eq $manifest -or $null -eq $manifest.skills) {
            Get-ChildItem -LiteralPath (Join-Path $repoRoot "skills") -Directory | ForEach-Object {
                Write-Host "- $($_.Name)"
            }
            return
        }

        $manifest.skills.PSObject.Properties | ForEach-Object {
            $description = ""
            if ($null -ne $_.Value.description) {
                $description = $_.Value.description
            }
            Write-Host ("- {0}：{1}" -f $_.Name, $description)
        }
    }
    catch {
        Write-Host "查询失败：$($_.Exception.Message)" -ForegroundColor Red
        Write-CodexSuggestion "建议确认网络可访问 GitHub，或指定正确仓库：$(Get-CodexInstallerCommand -Repo $Repo -Ref $Ref); Install-CodexSkill -List -Repo owner/repo -Ref main"
    }
    finally {
        if ((Test-Path -LiteralPath $tempRoot) -and (Test-CodexChildPath -Parent ([System.IO.Path]::GetTempPath()) -Child $tempRoot)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

function Install-CodexSkill {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Skill,

        [string]$Repo = $script:CodexSkillsDefaultRepo,

        [string]$Ref = $script:CodexSkillsDefaultRef,

        [switch]$Force,

        [switch]$List
    )

    try {
        if ($List) {
            Show-CodexSkillList -Repo $Repo -Ref $Ref
            return
        }

        if ([string]::IsNullOrWhiteSpace($Skill)) {
            Write-Host "缺少 Skill 名称。" -ForegroundColor Yellow
            Write-CodexSuggestion "查询可安装 skill：$(Get-CodexInstallerCommand -Repo $Repo -Ref $Ref); Install-CodexSkill -List"
            Write-CodexSuggestion "安装示例：$(Get-CodexInstallerCommand -Repo $Repo -Ref $Ref); Install-CodexSkill postgres-query"
            return
        }

        Assert-CodexSkillName -Name $Skill

        $installRoot = Get-CodexInstallRoot
        $dest = Join-Path $installRoot $Skill
        $backupRoot = Join-Path $installRoot ".backup"

        $resolvedInstallRoot = [System.IO.Path]::GetFullPath($installRoot)
        $resolvedDest = [System.IO.Path]::GetFullPath($dest)
        if (-not (Test-CodexChildPath -Parent $resolvedInstallRoot -Child $resolvedDest)) {
            throw "安装路径异常：$resolvedDest 不在当前执行目录 $resolvedInstallRoot 下。"
        }

        if ((Test-Path -LiteralPath $dest) -and -not $Force) {
            Write-Host "skill 已存在，未覆盖：$dest" -ForegroundColor Yellow
            Write-CodexSuggestion "覆盖安装：$(Get-CodexInstallerCommand -Repo $Repo -Ref $Ref); Install-CodexSkill $Skill -Force"
            Write-CodexSuggestion "换目录安装：cd <目标目录> 后重新执行安装命令。"
            return
        }

        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-skills-" + [System.Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

        try {
            $repoRoot = Get-CodexLocalRepoRoot
            if ($null -eq $repoRoot -or -not (Test-Path -LiteralPath (Join-Path $repoRoot "skills\$Skill") -PathType Container)) {
                Write-Host "正在下载 $Repo@$Ref ..."
                $repoRoot = Get-CodexRemoteRepoRoot -Repo $Repo -Ref $Ref -WorkDir $tempRoot
            }

            $src = Join-Path $repoRoot "skills\$Skill"
            if (-not (Test-Path -LiteralPath $src -PathType Container)) {
                Write-Host "未找到 skill：$Skill。仓库 $Repo@$Ref 中不存在 skills/$Skill。" -ForegroundColor Yellow
                Write-CodexSuggestion "查询可安装 skill：$(Get-CodexInstallerCommand -Repo $Repo -Ref $Ref); Install-CodexSkill -List"
                return
            }

            $skillFile = Join-Path $src "SKILL.md"
            if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
                throw "skill 无效：$Skill 缺少 SKILL.md。"
            }

            if (Test-Path -LiteralPath $dest) {
                New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $backupDest = Join-Path $backupRoot "$Skill-$timestamp"
                Move-Item -LiteralPath $dest -Destination $backupDest
                Write-Host "已备份旧 skill 到：$backupDest"
            }

            Copy-Item -LiteralPath $src -Destination $dest -Recurse
            Write-Host "安装完成：$dest" -ForegroundColor Green
        }
        finally {
            if ((Test-Path -LiteralPath $tempRoot) -and (Test-CodexChildPath -Parent ([System.IO.Path]::GetTempPath()) -Child $tempRoot)) {
                Remove-Item -LiteralPath $tempRoot -Recurse -Force
            }
        }
    }
    catch {
        Write-Host "安装失败：$($_.Exception.Message)" -ForegroundColor Red
        Write-CodexSuggestion "查询可安装 skill：$(Get-CodexInstallerCommand -Repo $Repo -Ref $Ref); Install-CodexSkill -List"
        Write-CodexSuggestion "安装示例：$(Get-CodexInstallerCommand -Repo $Repo -Ref $Ref); Install-CodexSkill postgres-query"
    }
}

if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    if ($args.Count -gt 0) {
        Install-CodexSkill @args
    }
    else {
        Write-Host "缺少参数。" -ForegroundColor Yellow
        Write-CodexSuggestion "查询可安装 skill：$(Get-CodexInstallerCommand); Install-CodexSkill -List"
        Write-CodexSuggestion "安装示例：$(Get-CodexInstallerCommand); Install-CodexSkill postgres-query"
    }
}
