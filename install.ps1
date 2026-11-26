param(
    [switch]$Force,
    [string]$TargetRoot = (Join-Path $HOME ".agents\skills")
)

$ErrorActionPreference = "Stop"

$sourceRoot = Join-Path $PSScriptRoot "skills"
$targetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
$manifestPath = Join-Path $targetRoot ".personal-ai-library-manifest.json"

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Skills folder not found: $sourceRoot"
}

New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
$targetRoot = [System.IO.Path]::GetFullPath($targetRoot)
$rootPrefix = $targetRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
$rootItem = Get-Item -LiteralPath $targetRoot -Force
if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Refusing to install through a linked target directory: $targetRoot"
}

function Get-FileHashValue {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-SafeTargetPath {
    param(
        [string]$RelativePath,
        [string]$ExpectedRoot
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [System.IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath -match '^[A-Za-z]:' -or
        $RelativePath -match '(^|[\\/])\.\.?([\\/]|$)') {
        throw "Unsafe path in installer manifest: $RelativePath"
    }

    $normalized = $RelativePath.Replace('/', '\')
    $parts = $normalized.Split([char]'\')
    if ($parts.Count -lt 2 -or $parts[0] -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
        $normalized -eq ".personal-ai-library-manifest.json") {
        throw "Invalid managed path in installer manifest: $RelativePath"
    }

    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $ExpectedRoot $normalized))
    if (-not $fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Manifest path escapes the installation folder: $RelativePath"
    }

    $parent = Split-Path -Parent $fullPath
    while ($parent -and $parent.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $parent) {
            $item = Get-Item -LiteralPath $parent -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to follow a linked directory in the installation path: $parent"
            }
        }
        $parent = Split-Path -Parent $parent
    }

    if (Test-Path -LiteralPath $fullPath) {
        $targetItem = Get-Item -LiteralPath $fullPath -Force
        if (($targetItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to write or remove a linked file: $fullPath"
        }
    }

    return $fullPath
}

$skillFolders = @(Get-ChildItem -LiteralPath $sourceRoot -Directory)
$sourceSkillNames = @($skillFolders | ForEach-Object { $_.Name })
$validSkillFolders = @()
foreach ($folder in $skillFolders) {
    if (Test-Path -LiteralPath (Join-Path $folder.FullName "SKILL.md") -PathType Leaf) {
        $validSkillFolders += $folder
    }
    else {
        Write-Warning "Skipping $($folder.Name): SKILL.md is missing"
    }
}

if ($validSkillFolders.Count -eq 0) {
    Write-Host "No valid skills found to install."
    exit 0
}

$managedFiles = @{}
$hasPreviousManifest = Test-Path -LiteralPath $manifestPath -PathType Leaf
if ($hasPreviousManifest) {
    $manifestItem = Get-Item -LiteralPath $manifestPath -Force
    if (($manifestItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to read or replace a linked installer manifest: $manifestPath"
    }
}

if ($hasPreviousManifest) {
    try {
        $previousManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        if ($previousManifest.version -ne 1 -or $null -eq $previousManifest.files) {
            throw "Unsupported manifest format."
        }

        foreach ($property in $previousManifest.files.PSObject.Properties) {
            $relativePath = [string]$property.Name
            $hash = [string]$property.Value
            if ($hash -notmatch '^[a-fA-F0-9]{64}$') {
                throw "Invalid SHA256 value for manifest path: $relativePath"
            }

            # Validate every stored path before using it for any filesystem operation.
            $null = Get-SafeTargetPath -RelativePath $relativePath -ExpectedRoot $targetRoot
            $managedFiles[$relativePath.Replace('/', '\')] = $hash.ToLowerInvariant()
        }
    }
    catch {
        throw "Cannot safely read installer manifest '$manifestPath': $($_.Exception.Message)"
    }
}

$processedSkills = @{}
foreach ($folder in $validSkillFolders) {
    $targetSkillDir = Join-Path $targetRoot $folder.Name

    $processedSkills[$folder.Name] = $true
    $sourceFiles = @(Get-ChildItem -LiteralPath $folder.FullName -File -Recurse)
    $copiedCount = 0
    $preservedCount = 0

    foreach ($sourceFile in $sourceFiles) {
        $relativePath = $sourceFile.FullName.Substring($sourceRoot.Length).TrimStart('\', '/')
        $relativePath = $relativePath.Replace('/', '\')
        $destinationPath = Get-SafeTargetPath -RelativePath $relativePath -ExpectedRoot $targetRoot
        $destinationDirectory = Split-Path -Parent $destinationPath
        $sourceHash = Get-FileHashValue -Path $sourceFile.FullName

        if ((Test-Path -LiteralPath $destinationPath -PathType Leaf) -and -not $Force) {
            $currentHash = Get-FileHashValue -Path $destinationPath
            if ($currentHash -eq $sourceHash) {
                # Adopt a complete file from an interrupted first install.
                $managedFiles[$relativePath] = $sourceHash
                continue
            }

            $wasManaged = $managedFiles.ContainsKey($relativePath)
            if (-not $wasManaged -or $currentHash -ne $managedFiles[$relativePath]) {
                # Never overwrite an untracked or user-modified file without -Force.
                $preservedCount++
                continue
            }
        }

        New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf) -or
            (Get-FileHashValue -Path $destinationPath) -ne $sourceHash) {
            # Copy to a sibling temporary file, then rename, so interruption
            # cannot leave a truncated managed destination behind.
            $temporaryPath = $destinationPath + "." + [guid]::NewGuid().ToString("N") + ".tmp"
            try {
                Copy-Item -LiteralPath $sourceFile.FullName -Destination $temporaryPath
                Move-Item -LiteralPath $temporaryPath -Destination $destinationPath -Force
            }
            finally {
                if (Test-Path -LiteralPath $temporaryPath) {
                    Remove-Item -LiteralPath $temporaryPath -Force
                }
            }
            $copiedCount++
        }
        $managedFiles[$relativePath] = $sourceHash
    }

    Write-Host "Installed/updated: $($folder.Name) (copied: $copiedCount; preserved: $preservedCount)"
}

if ($Force -and $hasPreviousManifest) {
    # A Skill removed from the repository is also eligible for safe cleanup:
    # its files are known from the previous manifest and are hash-checked below.
    foreach ($relativePath in @($managedFiles.Keys)) {
        $oldSkillName = ($relativePath -replace '/', '\').Split('\')[0]
        # Do not treat a present-but-invalid source folder as a removed Skill.
        if (($sourceSkillNames -notcontains $oldSkillName) -and
            -not $processedSkills.ContainsKey($oldSkillName)) {
            $processedSkills[$oldSkillName] = $true
        }
    }

    foreach ($relativePath in @($managedFiles.Keys)) {
        $skillName = ($relativePath -replace '/', '\').Split('\')[0]
        if (-not $processedSkills.ContainsKey($skillName)) {
            continue
        }

        $sourcePath = Join-Path $sourceRoot $relativePath
        if (Test-Path -LiteralPath $sourcePath -PathType Leaf) {
            continue
        }

        $staleTarget = Get-SafeTargetPath -RelativePath $relativePath -ExpectedRoot $targetRoot
        if (Test-Path -LiteralPath $staleTarget -PathType Leaf) {
            $currentHash = Get-FileHashValue -Path $staleTarget
            if ($currentHash -eq $managedFiles[$relativePath]) {
                Remove-Item -LiteralPath $staleTarget -Force
                Write-Host "Removed obsolete library file: $relativePath"
            }
            else {
                Write-Host "Preserved user-modified obsolete file: $relativePath"
            }
        }

        $managedFiles.Remove($relativePath)
    }
}

$manifestFiles = [ordered]@{}
foreach ($key in @($managedFiles.Keys | Sort-Object)) {
    $manifestFiles[$key] = $managedFiles[$key]
}

$manifest = [ordered]@{
    version = 1
    files = $manifestFiles
}
$json = $manifest | ConvertTo-Json -Depth 5
$tempManifest = Join-Path $targetRoot (".personal-ai-library-manifest-" + [guid]::NewGuid().ToString("N") + ".tmp")

try {
    [System.IO.File]::WriteAllText($tempManifest, $json, (New-Object System.Text.UTF8Encoding($false)))
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try {
            [System.IO.File]::Replace($tempManifest, $manifestPath, $null)
        }
        catch {
            Move-Item -LiteralPath $tempManifest -Destination $manifestPath -Force
        }
    }
    else {
        Move-Item -LiteralPath $tempManifest -Destination $manifestPath
    }
}
finally {
    if (Test-Path -LiteralPath $tempManifest) {
        Remove-Item -LiteralPath $tempManifest -Force
    }
}

Write-Host ""
Write-Host "Done. Codex skills folder: $targetRoot"
Write-Host "Installer manifest: $manifestPath"
Write-Host "Restart Codex if it is already running."
