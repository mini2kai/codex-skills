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

function Get-CodexRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $baseFull = [System.IO.Path]::GetFullPath($Base).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-CodexChildPath -Parent $baseFull -Child $pathFull)) {
        throw "路径异常：$pathFull 不在 $baseFull 下。"
    }

    $baseUriText = $baseFull
    if (-not $baseUriText.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $baseUriText += [System.IO.Path]::DirectorySeparatorChar
    }

    $baseUri = [System.Uri]::new($baseUriText)
    $pathUri = [System.Uri]::new($pathFull)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Get-CodexLocalConfigFiles {
    param([Parameter(Mandatory = $true)][string]$SkillRoot)

    if (-not (Test-Path -LiteralPath $SkillRoot -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $SkillRoot -File -Recurse | Where-Object {
            $_.Name -match '\.local\.(json|jsonc)$' -and
            $_.Name -notmatch '(?i)(state|cache|history|report|preview|worklog|ledger|output|result)'
        })
}

function Remove-CodexJsonComments {
    param([Parameter(Mandatory = $true)][string]$Text)

    $builder = [System.Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    $i = 0
    while ($i -lt $Text.Length) {
        $ch = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }

        if ($inString) {
            [void]$builder.Append($ch)
            if ($escaped) {
                $escaped = $false
            }
            elseif ($ch -eq '\') {
                $escaped = $true
            }
            elseif ($ch -eq '"') {
                $inString = $false
            }
            $i++
            continue
        }

        if ($ch -eq '"') {
            $inString = $true
            [void]$builder.Append($ch)
            $i++
            continue
        }

        if ($ch -eq '/' -and $next -eq '/') {
            while ($i -lt $Text.Length -and $Text[$i] -ne "`n") { $i++ }
            if ($i -lt $Text.Length) { [void]$builder.Append($Text[$i]); $i++ }
            continue
        }

        if ($ch -eq '/' -and $next -eq '*') {
            $i += 2
            while ($i + 1 -lt $Text.Length -and -not ($Text[$i] -eq '*' -and $Text[$i + 1] -eq '/')) { $i++ }
            $i += 2
            continue
        }

        [void]$builder.Append($ch)
        $i++
    }

    return $builder.ToString()
}

function Read-CodexJsonConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    if ($Path.EndsWith('.jsonc', [System.StringComparison]::OrdinalIgnoreCase)) {
        $text = Remove-CodexJsonComments -Text $text
    }

    return $text | ConvertFrom-Json
}

function Add-CodexSchemaPath {
    param(
        $Value,
        [System.Collections.Generic.HashSet[string]]$Paths,
        [string]$Prefix = ""
    )

    if ($null -eq $Value) {
        if (-not [string]::IsNullOrWhiteSpace($Prefix)) { [void]$Paths.Add($Prefix) }
        return
    }

    if ($Value -is [System.Array]) {
        $arrayPath = if ([string]::IsNullOrWhiteSpace($Prefix)) { "[]" } else { "$Prefix[]" }
        [void]$Paths.Add($arrayPath)
        foreach ($item in $Value) {
            Add-CodexSchemaPath -Value $item -Paths $Paths -Prefix $arrayPath
        }
        return
    }

    $properties = @($Value.PSObject.Properties | Where-Object { $_.MemberType -eq 'NoteProperty' })
    if ($properties.Count -eq 0) {
        if (-not [string]::IsNullOrWhiteSpace($Prefix)) { [void]$Paths.Add($Prefix) }
        return
    }

    foreach ($property in $properties) {
        $path = if ([string]::IsNullOrWhiteSpace($Prefix)) { $property.Name } else { "$Prefix.$($property.Name)" }
        [void]$Paths.Add($path)
        Add-CodexSchemaPath -Value $property.Value -Paths $Paths -Prefix $path
    }
}

function Get-CodexConfigSchema {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = Read-CodexJsonConfig -Path $Path
    $schemaSource = $data
    if ($null -ne $data.PSObject.Properties['_fieldDescriptions']) {
        $schemaSource = $data._fieldDescriptions
    }

    $paths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Add-CodexSchemaPath -Value $schemaSource -Paths $paths
    return @($paths | Sort-Object)
}

function Compare-CodexConfigSchema {
    param(
        [Parameter(Mandatory = $true)][string]$OldPath,
        [Parameter(Mandatory = $true)][string]$NewPath
    )

    try {
        $oldSchema = @(Get-CodexConfigSchema -Path $OldPath)
        $newSchema = @(Get-CodexConfigSchema -Path $NewPath)
    }
    catch {
        return @{ Compatible = $false; Reason = "配置文件解析失败：$($_.Exception.Message)" }
    }

    $diff = @(Compare-Object -ReferenceObject $newSchema -DifferenceObject $oldSchema)
    if ($diff.Count -eq 0) {
        return @{ Compatible = $true; Reason = "配置结构一致" }
    }

    $added = @($diff | Where-Object { $_.SideIndicator -eq '<=' } | Select-Object -First 8 -ExpandProperty InputObject)
    $removed = @($diff | Where-Object { $_.SideIndicator -eq '=>' } | Select-Object -First 8 -ExpandProperty InputObject)
    $parts = New-Object System.Collections.Generic.List[string]
    if ($added.Count -gt 0) { $parts.Add("新版新增字段：$($added -join ', ')") | Out-Null }
    if ($removed.Count -gt 0) { $parts.Add("旧版多出字段：$($removed -join ', ')") | Out-Null }

    return @{ Compatible = $false; Reason = ($parts -join '；') }
}

function Restore-CodexLocalConfigs {
    param(
        [Parameter(Mandatory = $true)][string]$BackupSkillRoot,
        [Parameter(Mandatory = $true)][string]$NewSkillRoot
    )

    $result = @{
        Restored = New-Object System.Collections.Generic.List[string]
        Skipped = New-Object System.Collections.Generic.List[string]
        Warnings = New-Object System.Collections.Generic.List[string]
    }

    foreach ($config in (Get-CodexLocalConfigFiles -SkillRoot $BackupSkillRoot)) {
        $relativePath = Get-CodexRelativePath -Base $BackupSkillRoot -Path $config.FullName
        $newPath = Join-Path $NewSkillRoot $relativePath
        $newFull = [System.IO.Path]::GetFullPath($newPath)
        if (-not (Test-CodexChildPath -Parent $NewSkillRoot -Child $newFull)) {
            $result.Warnings.Add("跳过异常配置路径：$relativePath") | Out-Null
            continue
        }

        if (Test-Path -LiteralPath $newFull -PathType Leaf) {
            $compare = Compare-CodexConfigSchema -OldPath $config.FullName -NewPath $newFull
            if (-not $compare.Compatible) {
                $result.Skipped.Add($relativePath) | Out-Null
                $result.Warnings.Add("配置文件有变化，请重新自行处理配置文件：$relativePath。$($compare.Reason)。旧配置已在备份中。") | Out-Null
                continue
            }
        }
        else {
            $result.Warnings.Add("新版没有同路径配置模板，已保留旧配置但无法校验结构：$relativePath。") | Out-Null
        }

        $parent = Split-Path -Parent $newFull
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Copy-Item -LiteralPath $config.FullName -Destination $newFull -Force
        $result.Restored.Add($relativePath) | Out-Null
    }

    return $result
}

function Test-CodexRuntimeArtifactFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    $normalized = $RelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $fileName = Split-Path -Leaf $normalized

    if ($normalized -match '(?i)(^|[\\/])(__pycache__|\.pytest_cache|logs|tmp|temp|cache)([\\/]|$)') {
        return $true
    }

    if ($fileName -match '(?i)\.(xlsx|xlsm|xls|log|tmp|bak|pyc)$') {
        return $true
    }

    if ($fileName -match '(?i)(state|cache|history|preview|ledger|output|result|worklog).*\.(json|jsonc)$') {
        return $true
    }

    if ($normalized -match '(?i)^data[\\/]' -and $fileName -match '(?i)\.local\.(json|jsonc)$') {
        return $true
    }

    return $false
}

function Copy-CodexSkillDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($file in (Get-ChildItem -LiteralPath $Source -File -Recurse -Force)) {
        $relativePath = Get-CodexRelativePath -Base $Source -Path $file.FullName
        if (Test-CodexRuntimeArtifactFile -RelativePath $relativePath) {
            continue
        }

        $targetPath = Join-Path $Destination $relativePath
        $targetFull = [System.IO.Path]::GetFullPath($targetPath)
        if (-not (Test-CodexChildPath -Parent $Destination -Child $targetFull)) {
            throw "复制路径异常：$targetFull 不在 $Destination 下。"
        }

        $targetParent = Split-Path -Parent $targetFull
        if (-not (Test-Path -LiteralPath $targetParent -PathType Container)) {
            New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
        }
        Copy-Item -LiteralPath $file.FullName -Destination $targetFull -Force
    }
}

function Get-CodexLockedFiles {
    param([Parameter(Mandatory = $true)][string]$Root)

    $locked = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return $locked
    }

    foreach ($file in (Get-ChildItem -LiteralPath $Root -File -Recurse -Force)) {
        $stream = $null
        try {
            $stream = [System.IO.File]::Open($file.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::None)
        }
        catch {
            $locked.Add((Get-CodexRelativePath -Base $Root -Path $file.FullName)) | Out-Null
        }
        finally {
            if ($null -ne $stream) {
                $stream.Dispose()
            }
        }
    }

    return $locked
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

    $manifestText = [System.IO.File]::ReadAllText($manifestPath, [System.Text.Encoding]::UTF8)
    return $manifestText | ConvertFrom-Json
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
            Write-CodexSuggestion "安装示例：$(Get-CodexInstallerCommand -Repo $Repo -Ref $Ref); Install-CodexSkill codex-skill-dev"
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

            $backupDest = $null
            if (Test-Path -LiteralPath $dest) {
                $lockedFiles = @(Get-CodexLockedFiles -Root $dest)
                if ($lockedFiles.Count -gt 0) {
                    throw "覆盖安装前发现旧 skill 文件正在被占用，请先关闭 Excel/WPS/编辑器后重试：$($lockedFiles -join ', ')"
                }

                New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
                $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
                $backupDest = Join-Path $backupRoot "$Skill-$timestamp"
                Move-Item -LiteralPath $dest -Destination $backupDest
                Write-Host "已备份旧 skill 到：$backupDest"
            }

            Copy-CodexSkillDirectory -Source $src -Destination $dest
            Write-Host "安装完成：$dest" -ForegroundColor Green

            if ($null -ne $backupDest) {
                $restoreResult = Restore-CodexLocalConfigs -BackupSkillRoot $backupDest -NewSkillRoot $dest
                if ($restoreResult.Restored.Count -gt 0) {
                    Write-Host "已保留本地配置文件：$($restoreResult.Restored -join ', ')" -ForegroundColor Green
                }
                else {
                    Write-Host "未发现可自动恢复的本地配置文件；生成文件仅保留在备份目录。" -ForegroundColor DarkGray
                }

                foreach ($item in $restoreResult.Skipped) {
                    Write-Host "未自动恢复配置：$item" -ForegroundColor Yellow
                }
                foreach ($warning in $restoreResult.Warnings) {
                    Write-Host $warning -ForegroundColor Yellow
                }
            }
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
        Write-CodexSuggestion "安装示例：$(Get-CodexInstallerCommand -Repo $Repo -Ref $Ref); Install-CodexSkill codex-skill-dev"
    }
}

if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    if ($args.Count -gt 0) {
        Install-CodexSkill @args
    }
    else {
        Write-Host "缺少参数。" -ForegroundColor Yellow
        Write-CodexSuggestion "查询可安装 skill：$(Get-CodexInstallerCommand); Install-CodexSkill -List"
        Write-CodexSuggestion "安装示例：$(Get-CodexInstallerCommand); Install-CodexSkill codex-skill-dev"
    }
}
