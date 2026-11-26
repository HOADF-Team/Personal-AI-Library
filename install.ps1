param(
    [switch]$Force,
    [string]$TargetRoot = (Join-Path $HOME ".agents\skills"),
    [int]$TestFailAfterMutation = 0
)

$ErrorActionPreference = "Stop"

$sourceRoot = Join-Path $PSScriptRoot "skills"
$targetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
$manifestPath = Join-Path $targetRoot ".personal-ai-library-manifest.json"

if (-not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
    throw "Skills folder not found: $sourceRoot"
}

# Check the nearest existing ancestor before creating anything. Checking only
# TargetRoot itself misses a linked parent such as ~/.agents -> another folder.
$ancestor = $targetRoot
while ($ancestor -and -not (Test-Path -LiteralPath $ancestor)) {
    $parent = Split-Path -Parent $ancestor
    if (-not $parent -or $parent -eq $ancestor) {
        break
    }
    $ancestor = $parent
}
while ($ancestor -and (Test-Path -LiteralPath $ancestor)) {
    $ancestorItem = Get-Item -LiteralPath $ancestor -Force
    if (($ancestorItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to install through a linked target path component: $ancestor"
    }
    $parent = Split-Path -Parent $ancestor
    if (-not $parent -or $parent -eq $ancestor) {
        break
    }
    $ancestor = $parent
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


$transactionRoot = Join-Path $targetRoot ".personal-ai-library-transaction"
$journalPath = Join-Path $transactionRoot "journal.json"
function Write-AtomicText {
    param([string]$Path, [string]$Content)
    $temporary = $Path + "." + [guid]::NewGuid().ToString("N") + ".tmp"
    try {
        [System.IO.File]::WriteAllText($temporary, $Content, (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try { [System.IO.File]::Replace($temporary, $Path, $null) }
            catch { Move-Item -LiteralPath $temporary -Destination $Path -Force }
        } else { Move-Item -LiteralPath $temporary -Destination $Path }
    }
    finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force } }
}

# Recover before reading the old manifest or changing destination files.
if (Test-Path -LiteralPath $transactionRoot) {
    $txItem = Get-Item -LiteralPath $transactionRoot -Force
    if (($txItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to use a linked installer transaction directory."
    }
    if (Test-Path -LiteralPath $journalPath -PathType Leaf) {
        $journalItem = Get-Item -LiteralPath $journalPath -Force
        if (($journalItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to read a linked installer transaction journal."
        }
        $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        if ($journal.version -ne 1 -or $null -eq $journal.entries) {
            throw "Installer transaction journal is invalid; refusing to modify the installation."
        }
        foreach ($entry in $journal.entries) {
            $relative = [string]$entry.path
            if ($relative -eq ".personal-ai-library-manifest.json") {
                $destination = $manifestPath
                if (Test-Path -LiteralPath $destination) {
                    $item = Get-Item -LiteralPath $destination -Force
                    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw "Recovery refused a linked installer manifest."
                    }
                }
            } else {
                $destination = Get-SafeTargetPath -RelativePath $relative -ExpectedRoot $targetRoot
            }
            $exists = Test-Path -LiteralPath $destination -PathType Leaf
            $currentHash = if ($exists) { Get-FileHashValue -Path $destination } else { "" }
            $originalHash = [string]$entry.original_hash
            $expectedHash = [string]$entry.expected_hash
            if ($exists -and $currentHash -ne $originalHash -and
                (-not $expectedHash -or $currentHash -ne $expectedHash)) {
                throw "Recovery stopped because a file changed after interruption: $relative. Journal retained."
            }
            if ([bool]$entry.existed) {
                if ($currentHash -ne $originalHash) {
                    $backupRelative = [string]$entry.backup
                    if ($backupRelative -notmatch '^backup\\(?:[A-Fa-f0-9-]+\.bak|manifest\.bak)
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


# Back up every possible destination touched by this run before committing changes.
New-Item -ItemType Directory -Force -Path $transactionRoot | Out-Null
$backupRoot = Join-Path $transactionRoot "backup"
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
$transactionEntries = @()
$candidates = @{}
foreach ($folder in $validSkillFolders) {
    foreach ($file in @(Get-ChildItem -LiteralPath $folder.FullName -File -Recurse)) {
        $rel = $file.FullName.Substring($sourceRoot.Length).TrimStart('\', '/').Replace('/', '\')
        $candidates[$rel] = Get-FileHashValue -Path $file.FullName
    }
}
foreach ($rel in @($managedFiles.Keys)) {
    if (-not $candidates.ContainsKey($rel)) { $candidates[$rel] = "" }
}
foreach ($rel in @($candidates.Keys | Sort-Object)) {
    $dest = Get-SafeTargetPath -RelativePath $rel -ExpectedRoot $targetRoot
    $exists = Test-Path -LiteralPath $dest -PathType Leaf
    $originalHash = if ($exists) { Get-FileHashValue -Path $dest } else { "" }
    $backupName = [guid]::NewGuid().ToString("N") + ".bak"
    if ($exists) {
        Copy-Item -LiteralPath $dest -Destination (Join-Path $backupRoot $backupName)
        if ((Get-FileHashValue -Path (Join-Path $backupRoot $backupName)) -ne $originalHash) {
            throw "Could not verify transaction backup for: $rel"
        }
    }
    $transactionEntries += [ordered]@{
        path = $rel
        existed = $exists
        original_hash = $originalHash
        expected_hash = [string]$candidates[$rel]
        backup = if ($exists) { "backup\$backupName" } else { "" }
    }
}
$manifestExisted = Test-Path -LiteralPath $manifestPath -PathType Leaf
$manifestOriginalHash = if ($manifestExisted) { Get-FileHashValue -Path $manifestPath } else { "" }
if ($manifestExisted) {
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $backupRoot "manifest.bak")
    if ((Get-FileHashValue -Path (Join-Path $backupRoot "manifest.bak")) -ne $manifestOriginalHash) {
        throw "Could not verify installer manifest backup."
    }
}
$manifestEntry = [ordered]@{
    path = ".personal-ai-library-manifest.json"
    existed = $manifestExisted
    original_hash = $manifestOriginalHash
    expected_hash = ""
    backup = if ($manifestExisted) { "backup\manifest.bak" } else { "" }
}
$transactionEntries += $manifestEntry
$journal = [ordered]@{ version = 1; entries = $transactionEntries }
Write-AtomicText -Path $journalPath -Content ($journal | ConvertTo-Json -Depth 8)
$script:installerMutationCount = 0
function Register-InstallerMutation {
    $script:installerMutationCount++
    if ($TestFailAfterMutation -gt 0 -and $script:installerMutationCount -ge $TestFailAfterMutation) {
        throw "Simulated installer interruption after mutation $script:installerMutationCount."
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
            Register-InstallerMutation
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
                Register-InstallerMutation
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

$manifestEntry.expected_hash = [System.BitConverter]::ToString(
    (New-Object System.Security.Cryptography.SHA256Managed).ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($json)
    )
).Replace("-", "").ToLowerInvariant()
Write-AtomicText -Path $journalPath -Content ($journal | ConvertTo-Json -Depth 8)

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
Remove-Item -LiteralPath $transactionRoot -Recurse -Force
Write-Host "Done. Codex skills folder: $targetRoot"
Write-Host "Installer manifest: $manifestPath"
Write-Host "Restart Codex if it is already running."
) {
                        throw "Recovery journal contains an unsafe backup path. Journal retained."
                    }
                    $backup = Join-Path $transactionRoot $backupRelative
                    if (-not (Test-Path -LiteralPath $backup -PathType Leaf) -or
                        (Get-FileHashValue -Path $backup) -ne $originalHash) {
                        throw "Recovery backup is missing or invalid for: $relative. Journal retained."
                    }
                    $parent = Split-Path -Parent $destination
                    New-Item -ItemType Directory -Force -Path $parent | Out-Null
                    $restoreTemp = $destination + "." + [guid]::NewGuid().ToString("N") + ".restore"
                    try {
                        Copy-Item -LiteralPath $backup -Destination $restoreTemp
                        Move-Item -LiteralPath $restoreTemp -Destination $destination -Force
                    } finally {
                        if (Test-Path -LiteralPath $restoreTemp) { Remove-Item -LiteralPath $restoreTemp -Force }
                    }
                }
            } elseif ($exists) {
                if (-not $expectedHash -or $currentHash -ne $expectedHash) {
                    throw "Recovery refused to remove an unexpected file: $relative. Journal retained."
                }
                Remove-Item -LiteralPath $destination -Force
            }
        }
        Remove-Item -LiteralPath $transactionRoot -Recurse -Force
        Write-Host "Recovered the previous installation after an interrupted update."
    } else {
        Remove-Item -LiteralPath $transactionRoot -Recurse -Force
    }
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
