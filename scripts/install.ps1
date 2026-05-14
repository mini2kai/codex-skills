[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Skill,

    [string]$Repo = "mini2kai/codex-skills",

    [string]$Ref = "main",

    [switch]$Force,

    [switch]$List
)

Set-StrictMode -Version Latest

function Get-CodexUserHome {
    $homePath = [Environment]::GetFolderPath("UserProfile")
    if ([string]::IsNullOrWhiteSpace($homePath)) {
        $homePath = $HOME
    }
    if ([string]::IsNullOrWhiteSpace($homePath)) {
        throw "Cannot determine the current user's home directory."
    }
    return $homePath
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
        throw "Invalid skill name '$Name'. Use only letters, numbers, dot, underscore, and hyphen."
    }
}

function Get-CodexSkillsRoot {
    $userHome = Get-CodexUserHome
    return (Join-Path $userHome ".codex\skills")
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

    throw "Failed to download repository archive for $Repo@$Ref.`n$($errors -join "`n")"
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

    $children = Get-ChildItem -LiteralPath $extractPath -Directory
    if ($children.Count -eq 0) {
        throw "Downloaded archive from $url did not contain a repository directory."
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
        [string]$Repo = "mini2kai/codex-skills",
        [string]$Ref = "main"
    )

    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-skills-" + [System.Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        $repoRoot = Get-CodexLocalRepoRoot
        if ($null -eq $repoRoot) {
            $repoRoot = Get-CodexRemoteRepoRoot -Repo $Repo -Ref $Ref -WorkDir $tempRoot
        }

        $manifest = Get-CodexSkillManifest -RepoRoot $repoRoot
        if ($null -eq $manifest -or $null -eq $manifest.skills) {
            Get-ChildItem -LiteralPath (Join-Path $repoRoot "skills") -Directory | ForEach-Object { $_.Name }
            return
        }

        $manifest.skills.PSObject.Properties | ForEach-Object {
            $description = ""
            if ($null -ne $_.Value.description) {
                $description = $_.Value.description
            }
            "{0}`t{1}" -f $_.Name, $description
        }
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

        [string]$Repo = "mini2kai/codex-skills",

        [string]$Ref = "main",

        [switch]$Force,

        [switch]$List
    )

    if ($List) {
        Show-CodexSkillList -Repo $Repo -Ref $Ref
        return
    }

    if ([string]::IsNullOrWhiteSpace($Skill)) {
        throw "Usage: Install-CodexSkill <skill-name> [-Repo owner/repo] [-Ref main|tag] [-Force] [-List]"
    }

    Assert-CodexSkillName -Name $Skill

    $skillsRoot = Get-CodexSkillsRoot
    $dest = Join-Path $skillsRoot $Skill
    $backupRoot = Join-Path $skillsRoot ".backup"
    $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-skills-" + [System.Guid]::NewGuid().ToString("N"))

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

    try {
        $repoRoot = Get-CodexLocalRepoRoot
        if ($null -eq $repoRoot -or -not (Test-Path -LiteralPath (Join-Path $repoRoot "skills\$Skill") -PathType Container)) {
            Write-Host "Downloading $Repo@$Ref..."
            $repoRoot = Get-CodexRemoteRepoRoot -Repo $Repo -Ref $Ref -WorkDir $tempRoot
        }

        $src = Join-Path $repoRoot "skills\$Skill"
        if (-not (Test-Path -LiteralPath $src -PathType Container)) {
            throw "Skill '$Skill' was not found at skills/$Skill in $Repo@$Ref. Use -List to view available skills."
        }

        $skillFile = Join-Path $src "SKILL.md"
        if (-not (Test-Path -LiteralPath $skillFile -PathType Leaf)) {
            throw "Skill '$Skill' is invalid: SKILL.md is missing."
        }

        New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
        $resolvedSkillsRoot = [System.IO.Path]::GetFullPath($skillsRoot)
        $resolvedDest = [System.IO.Path]::GetFullPath($dest)
        if (-not (Test-CodexChildPath -Parent $resolvedSkillsRoot -Child $resolvedDest)) {
            throw "Resolved install path is outside the Codex skills directory: $resolvedDest"
        }

        if (Test-Path -LiteralPath $dest) {
            if (-not $Force) {
                throw "Skill '$Skill' already exists at $dest. Re-run with -Force to replace it and create a backup."
            }

            New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupDest = Join-Path $backupRoot "$Skill-$timestamp"
            Move-Item -LiteralPath $dest -Destination $backupDest
            Write-Host "Existing skill backed up to $backupDest"
        }

        Copy-Item -LiteralPath $src -Destination $dest -Recurse
        Write-Host "Installed '$Skill' to $dest"
        Write-Host "Restart Codex to load the installed skill."
    }
    finally {
        if ((Test-Path -LiteralPath $tempRoot) -and (Test-CodexChildPath -Parent ([System.IO.Path]::GetTempPath()) -Child $tempRoot)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force
        }
    }
}

if ($MyInvocation.InvocationName -ne ".") {
    if ($PSBoundParameters.Count -gt 0 -or $args.Count -gt 0) {
        Install-CodexSkill @PSBoundParameters
    }
}

