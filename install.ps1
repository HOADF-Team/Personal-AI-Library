param(
    [switch]$Force,
    [int]$TestFailAfterChanges = 0,
    [string]$TargetRoot = (Join-Path $HOME ".agents\skills")
)

$ErrorActionPreference = "Stop"

$sourceRoot = Join-Path $PSScriptRoot "skills"
$targetRoot = [System.IO.Path]::GetFullPath($TargetRoot)
$manifestPath = Join-Path $targetRoot ".personal-ai-library-manifest.json"
$transactionPath = Join-Path $targetRoot ".personal-ai-library-transaction.json"

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


function Restore-InterruptedTransaction {
    if (-not (Test-Path -LiteralPath $transactionPath -PathType Leaf)) { return }

    $journalItem = Get-Item -LiteralPath $transactionPath -Force
    if (($journalItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to read a linked transaction journal: $transactionPath"
    }
    $journal = Get-Content -LiteralPath $transactionPath -Raw | ConvertFrom-Json
    if ($journal.version -ne 1 -or
        [string]$journal.backup_directory -notmatch '^\.personal-ai-library-rollback-[a-fA-F0-9]{32}
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


# Snapshot every destination that this run may replace or remove. Publish the
# journal only after all backups are complete and before the first mutation.
if (Test-Path -LiteralPath $transactionPath) {
    throw "A transaction journal remains after recovery: $transactionPath"
}
$transactionId = [guid]::NewGuid().ToString("N")
$backupDirectoryName = ".personal-ai-library-rollback-$transactionId"
$backupRoot = Join-Path $targetRoot $backupDirectoryName
New-Item -ItemType Directory -Path $backupRoot | Out-Null

$pathsToSnapshot = @{}
foreach ($relativePath in @($managedFiles.Keys)) {
    $pathsToSnapshot[$relativePath.Replace('/', '\')] = $true
}
foreach ($folder in $validSkillFolders) {
    foreach ($sourceFile in @(Get-ChildItem -LiteralPath $folder.FullName -File -Recurse)) {
        $relativePath = $sourceFile.FullName.Substring($sourceRoot.Length).TrimStart('\', '/').Replace('/', '\')
        $pathsToSnapshot[$relativePath] = $true
    }
}

$journalEntries = @()
$backupIndex = 0
foreach ($relativePath in @($pathsToSnapshot.Keys | Sort-Object)) {
    $destination = Get-SafeTargetPath -RelativePath $relativePath -ExpectedRoot $targetRoot
    $existed = Test-Path -LiteralPath $destination -PathType Leaf
    $backupName = $null
    if ($existed) {
        $backupIndex++
        $backupName = "{0:D6}.bak" -f $backupIndex
        Copy-Item -LiteralPath $destination -Destination (Join-Path $backupRoot $backupName)
    }
    $journalEntries += [ordered]@{ path = $relativePath; existed = [bool]$existed; backup = $backupName }
}
$manifestExisted = Test-Path -LiteralPath $manifestPath -PathType Leaf
if ($manifestExisted) {
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $backupRoot "manifest.bak")
}
$journal = [ordered]@{
    version = 1
    backup_directory = $backupDirectoryName
    manifest_existed = [bool]$manifestExisted
    entries = $journalEntries
}
$journalTemp = $transactionPath + "." + [guid]::NewGuid().ToString("N") + ".tmp"
try {
    [System.IO.File]::WriteAllText($journalTemp, ($journal | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $journalTemp -Destination $transactionPath
}
finally {
    if (Test-Path -LiteralPath $journalTemp) { Remove-Item -LiteralPath $journalTemp -Force }
}
$transactionChanges = 0

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
            $transactionChanges++
            if ($TestFailAfterChanges -gt 0 -and $transactionChanges -ge $TestFailAfterChanges) { throw "Injected installer failure for recovery testing." }
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
                $transactionChanges++
                if ($TestFailAfterChanges -gt 0 -and $transactionChanges -ge $TestFailAfterChanges) { throw "Injected installer failure for recovery testing." }
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
Remove-Item -LiteralPath $transactionPath -Force
Remove-Item -LiteralPath $backupRoot -Recurse -Force
Write-Host "Restart Codex if it is already running."
) {
        throw "Invalid or unsupported installer transaction journal: $transactionPath"
    }

    $backupRoot = Join-Path $targetRoot ([string]$journal.backup_directory)
    if (-not (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        throw "Transaction backup is missing; refusing to continue: $backupRoot"
    }
    $backupItem = Get-Item -LiteralPath $backupRoot -Force
    if (($backupItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to restore from a linked transaction backup: $backupRoot"
    }

    foreach ($entry in @($journal.entries)) {
        $destination = Get-SafeTargetPath -RelativePath ([string]$entry.path) -ExpectedRoot $targetRoot
        if ([bool]$entry.existed) {
            $backupName = [string]$entry.backup
            if ($backupName -notmatch '^[0-9]{6}\.bak
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
Remove-Item -LiteralPath $transactionPath -Force
Remove-Item -LiteralPath $backupRoot -Recurse -Force
Write-Host "Restart Codex if it is already running."
) { throw "Invalid backup entry in transaction journal." }
            $backupFile = Join-Path $backupRoot $backupName
            if (-not (Test-Path -LiteralPath $backupFile -PathType Leaf)) {
                throw "Transaction file backup is missing: $backupFile"
            }
            $destinationDirectory = Split-Path -Parent $destination
            New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
            $restoreTemp = $destination + "." + [guid]::NewGuid().ToString("N") + ".restore"
            try {
                Copy-Item -LiteralPath $backupFile -Destination $restoreTemp
                Move-Item -LiteralPath $restoreTemp -Destination $destination -Force
            }
            finally {
                if (Test-Path -LiteralPath $restoreTemp) { Remove-Item -LiteralPath $restoreTemp -Force }
            }
        }
        elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
            Remove-Item -LiteralPath $destination -Force
        }
    }

    if ([bool]$journal.manifest_existed) {
        $manifestBackup = Join-Path $backupRoot "manifest.bak"
        if (-not (Test-Path -LiteralPath $manifestBackup -PathType Leaf)) {
            throw "Transaction manifest backup is missing: $manifestBackup"
        }
        $manifestTemp = $manifestPath + "." + [guid]::NewGuid().ToString("N") + ".restore"
        try {
            Copy-Item -LiteralPath $manifestBackup -Destination $manifestTemp
            Move-Item -LiteralPath $manifestTemp -Destination $manifestPath -Force
        }
        finally {
            if (Test-Path -LiteralPath $manifestTemp) { Remove-Item -LiteralPath $manifestTemp -Force }
        }
    }
    elseif (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        Remove-Item -LiteralPath $manifestPath -Force
    }

    Remove-Item -LiteralPath $transactionPath -Force
    Remove-Item -LiteralPath $backupRoot -Recurse -Force
    Write-Warning "Recovered an interrupted installation by restoring the previous state."
}

Restore-InterruptedTransaction

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
Remove-Item -LiteralPath $transactionPath -Force
Remove-Item -LiteralPath $backupRoot -Recurse -Force
Write-Host "Restart Codex if it is already running."
