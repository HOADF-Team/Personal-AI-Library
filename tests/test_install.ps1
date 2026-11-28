$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repoRoot "install.ps1"
$targetRoot = Join-Path $env:TEMP ("Personal-AI-Library-Test-" + [guid]::NewGuid().ToString("N"))
$outsideFile = Join-Path (Split-Path -Parent $targetRoot) "Personal-AI-Library-outside-test.txt"
$manifestPath = Join-Path $targetRoot ".personal-ai-library-manifest.json"
$invalidSkillName = "incomplete-skill-" + [guid]::NewGuid().ToString("N")
$invalidSourceDir = Join-Path $repoRoot ("skills\" + $invalidSkillName)
$linkedParent = Join-Path $env:TEMP ("Personal-AI-Library-Junction-" + [guid]::NewGuid().ToString("N"))
$realParent = Join-Path $env:TEMP ("Personal-AI-Library-Real-" + [guid]::NewGuid().ToString("N"))
$rollbackRoot = Join-Path $env:TEMP ("Personal-AI-Library-Rollback-" + [guid]::NewGuid().ToString("N"))
$versionA = Join-Path $rollbackRoot "version-a"
$versionB = Join-Path $rollbackRoot "version-b"
$rollbackTarget = Join-Path $rollbackRoot "installed"
$sourceLinkTarget = Join-Path $env:TEMP ("Personal-AI-Library-Source-Link-Target-" + [guid]::NewGuid().ToString("N"))
$sourceLinkedDir = Join-Path $repoRoot "skills\code-audit\_linked-source-test"

function Add-ManifestEntry {
    param([string]$RelativePath, [string]$FilePath)

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $files = @{}
    foreach ($property in $manifest.files.PSObject.Properties) {
        $files[$property.Name] = [string]$property.Value
    }

    $files[$RelativePath] = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $updated = [ordered]@{ version = 1; files = $files } | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $manifestPath -Value $updated -Encoding UTF8
}

try {
    # A second process must not enter the installer while the target is locked.
    New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
    $lockPath = Join-Path $targetRoot ".personal-ai-library-install.lock"
    $heldLock = [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
    )
    $concurrentRunRejected = $false
    try {
        & $installer -TargetRoot $targetRoot
    }
    catch {
        if ($_.Exception.Message -match "Another Personal AI Library installer is already running") {
            $concurrentRunRejected = $true
        }
        else {
            throw
        }
    }
    finally {
        $heldLock.Dispose()
    }
    if (-not $concurrentRunRejected) {
        throw "Installer did not reject a concurrent run for the same target."
    }

    & $installer -TargetRoot $targetRoot

    $skillFile = Join-Path $targetRoot "code-audit\SKILL.md"
    $referenceFile = Join-Path $targetRoot "code-audit\references\python-ast-audit.md"
    $scriptFile = Join-Path $targetRoot "code-audit\scripts\python_ast_audit.py"

    foreach ($path in @($skillFile, $referenceFile, $scriptFile)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Expected installed file is missing: $path"
        }
    }

    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Installer manifest was not created."
    }

    # Verify a manifest-less reinstall adopts complete files and restores
    # a missing file. This does not simulate a process crash.
    Remove-Item -LiteralPath $manifestPath -Force
    Remove-Item -LiteralPath $referenceFile -Force
    & $installer -TargetRoot $targetRoot
    if (-not (Test-Path -LiteralPath $referenceFile -PathType Leaf)) {
        throw "A manifest-less interrupted install did not restore a missing file."
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Recovery did not recreate the installer manifest."
    }

    $localFile = Join-Path $targetRoot "code-audit\user-local-note.txt"
    Set-Content -LiteralPath $localFile -Value "keep me" -Encoding UTF8
    Set-Content -LiteralPath $skillFile -Value "local modified copy" -Encoding UTF8

    & $installer -TargetRoot $targetRoot
    if ((Get-Content -LiteralPath $skillFile -Raw) -notmatch "local modified copy") {
        throw "Without -Force, existing skill files should remain unchanged."
    }

    # Verify a later reinstall restores a missing managed file while leaving
    # an existing user-modified file untouched.
    Remove-Item -LiteralPath $referenceFile -Force
    & $installer -TargetRoot $targetRoot
    if (-not (Test-Path -LiteralPath $referenceFile -PathType Leaf)) {
        throw "A subsequent install did not restore a missing managed file."
    }
    if ((Get-Content -LiteralPath $skillFile -Raw) -notmatch "local modified copy") {
        throw "Recovery overwrote a user-modified managed file."
    }

    & $installer -Force -TargetRoot $targetRoot
    if (-not (Test-Path -LiteralPath $localFile -PathType Leaf)) {
        throw "Force update removed a user-created file."
    }

    $sourceSkill = Join-Path $repoRoot "skills\code-audit\SKILL.md"
    if ((Get-Content -LiteralPath $skillFile -Raw) -ne (Get-Content -LiteralPath $sourceSkill -Raw)) {
        throw "Force update did not replace the skill with the repository version."
    }

    # Simulate files removed from a newer library version.
    $obsoleteFile = Join-Path $targetRoot "code-audit\references\obsolete-library-file.md"
    $modifiedObsoleteFile = Join-Path $targetRoot "code-audit\references\obsolete-user-edited-file.md"
    $retiredSkillFile = Join-Path $targetRoot "retired-skill\SKILL.md"
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $obsoleteFile) | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $retiredSkillFile) | Out-Null
    Set-Content -LiteralPath $obsoleteFile -Value "old library content" -Encoding UTF8
    Set-Content -LiteralPath $modifiedObsoleteFile -Value "old library content" -Encoding UTF8
    Set-Content -LiteralPath $retiredSkillFile -Value "retired skill content" -Encoding UTF8
    Add-ManifestEntry -RelativePath "code-audit\references\obsolete-library-file.md" -FilePath $obsoleteFile
    Add-ManifestEntry -RelativePath "code-audit\references\obsolete-user-edited-file.md" -FilePath $modifiedObsoleteFile
    Add-ManifestEntry -RelativePath "retired-skill\SKILL.md" -FilePath $retiredSkillFile
    Set-Content -LiteralPath $modifiedObsoleteFile -Value "user changed this file" -Encoding UTF8

    & $installer -Force -TargetRoot $targetRoot

    if (Test-Path -LiteralPath $obsoleteFile) {
        throw "Unchanged obsolete library file was not removed."
    }
    if (-not (Test-Path -LiteralPath $modifiedObsoleteFile -PathType Leaf)) {
        throw "User-modified obsolete file was removed."
    }
    if (Test-Path -LiteralPath $retiredSkillFile -PathType Leaf) {
        throw "Obsolete file from a removed Skill was not cleaned up."
    }
    if (-not (Test-Path -LiteralPath $localFile -PathType Leaf)) {
        throw "Force update removed a user-created file."
    }

    # A source folder without SKILL.md is invalid, but is not a deleted Skill.
    $invalidTargetFile = Join-Path $targetRoot ($invalidSkillName + "\legacy.md")
    New-Item -ItemType Directory -Force -Path $invalidSourceDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $invalidTargetFile) | Out-Null
    Set-Content -LiteralPath (Join-Path $invalidSourceDir "README.txt") -Value "incomplete source" -Encoding UTF8
    Set-Content -LiteralPath $invalidTargetFile -Value "preserve existing installation" -Encoding UTF8
    Add-ManifestEntry -RelativePath ($invalidSkillName + "\legacy.md") -FilePath $invalidTargetFile
    & $installer -Force -TargetRoot $targetRoot
    if (-not (Test-Path -LiteralPath $invalidTargetFile -PathType Leaf)) {
        throw "Installer removed files for a source folder that only lacks SKILL.md."
    }

    # Verify a user can roll back by running an older extracted release with -Force.
    foreach ($versionDir in @($versionA, $versionB)) {
        New-Item -ItemType Directory -Force -Path (Join-Path $versionDir "skills\sample-skill") | Out-Null
        Copy-Item -LiteralPath $installer -Destination (Join-Path $versionDir "install.ps1")
    }
    Set-Content -LiteralPath (Join-Path $versionA "skills\sample-skill\SKILL.md") -Value "version A" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $versionA "skills\sample-skill\legacy.md") -Value "only in A" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $versionB "skills\sample-skill\SKILL.md") -Value "version B" -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $versionB "skills\sample-skill\new.md") -Value "only in B" -Encoding UTF8

    & (Join-Path $versionA "install.ps1") -TargetRoot $rollbackTarget
    & (Join-Path $versionB "install.ps1") -Force -TargetRoot $rollbackTarget
    if ((Get-Content -LiteralPath (Join-Path $rollbackTarget "sample-skill\SKILL.md") -Raw).Trim() -ne "version B") {
        throw "The newer test release was not installed before rollback."
    }

    & (Join-Path $versionA "install.ps1") -Force -TargetRoot $rollbackTarget
    if ((Get-Content -LiteralPath (Join-Path $rollbackTarget "sample-skill\SKILL.md") -Raw).Trim() -ne "version A") {
        throw "Rollback did not restore the previous Skill content."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $rollbackTarget "sample-skill\legacy.md") -PathType Leaf)) {
        throw "Rollback did not restore a file removed by the newer version."
    }
    if (Test-Path -LiteralPath (Join-Path $rollbackTarget "sample-skill\new.md")) {
        throw "Rollback did not remove a file introduced by the newer version."
    }

    # Simulate a process interruption after the newer version has changed at
    # least one destination. The next invocation must restore the exact prior
    # release before continuing.
    $interrupted = $false
    try {
        & (Join-Path $versionB "install.ps1") -Force -TestFailAfterChanges 3 -TargetRoot $rollbackTarget
    }
    catch {
        if ($_.Exception.Message -match "Injected installer failure") {
            $interrupted = $true
        }
        else {
            throw
        }
    }
    if (-not $interrupted) {
        throw "The installer failure-injection point was not reached."
    }

    & (Join-Path $versionA "install.ps1") -TargetRoot $rollbackTarget
    if ((Get-Content -LiteralPath (Join-Path $rollbackTarget "sample-skill\\SKILL.md") -Raw).Trim() -ne "version A") {
        throw "Interrupted update recovery did not restore the previous Skill version."
    }
    if (-not (Test-Path -LiteralPath (Join-Path $rollbackTarget "sample-skill\\legacy.md") -PathType Leaf)) {
        throw "Interrupted update recovery did not restore the previous release's removed file."
    }
    if (Test-Path -LiteralPath (Join-Path $rollbackTarget "sample-skill\\new.md")) {
        throw "Interrupted update recovery left a file introduced by the failed update."
    }
    if (Test-Path -LiteralPath (Join-Path $rollbackTarget ".personal-ai-library-transaction.json")) {
        throw "Interrupted update recovery left its transaction journal behind."
    }

    # A linked parent directory must be rejected before the installer creates
    # the target directory through that link.
    New-Item -ItemType Directory -Path $realParent | Out-Null
    New-Item -ItemType Junction -Path $linkedParent -Target $realParent | Out-Null
    $linkedTarget = Join-Path $linkedParent "skills"
    $linkedParentRejected = $false
    try {
        & $installer -TargetRoot $linkedTarget
    }
    catch {
        $linkedParentRejected = $true
    }
    if (-not $linkedParentRejected) {
        throw "Installer accepted a target path with a linked parent directory."
    }
    if (Test-Path -LiteralPath $linkedTarget) {
        throw "Installer created the target directory through a linked parent before rejecting it."
    }

    # A linked source directory must be rejected before external files can be copied.
    New-Item -ItemType Directory -Path $sourceLinkTarget | Out-Null
    Set-Content -LiteralPath (Join-Path $sourceLinkTarget "outside-secret.txt") -Value "must not be installed" -Encoding UTF8
    New-Item -ItemType Junction -Path $sourceLinkedDir -Target $sourceLinkTarget | Out-Null
    $sourceLinkRejected = $false
    try {
        & $installer -TargetRoot $targetRoot
    }
    catch {
        if ($_.Exception.Message -match "Refusing to install a linked source entry") {
            $sourceLinkRejected = $true
        }
        else {
            throw
        }
    }
    if (-not $sourceLinkRejected) {
        throw "Installer accepted a linked source directory."
    }
    if (Test-Path -LiteralPath (Join-Path $targetRoot "code-audit\_linked-source-test\outside-secret.txt")) {
        throw "Installer copied a file from outside the Skills source tree."
    }
    [System.IO.Directory]::Delete($sourceLinkedDir)
    Remove-Item -LiteralPath $sourceLinkTarget -Recurse -Force

    # A linked rollback backup must not be followed during transaction recovery.
    $linkedBackupDirectoryName = ".personal-ai-library-rollback-" + [guid]::NewGuid().ToString("N")
    $linkedBackupRoot = Join-Path $targetRoot $linkedBackupDirectoryName
    New-Item -ItemType Directory -Path $linkedBackupRoot | Out-Null
    Set-Content -LiteralPath $outsideFile -Value "external backup target" -Encoding UTF8
    Set-Content -LiteralPath $skillFile -Value "preserve installed file" -Encoding UTF8
    New-Item -ItemType SymbolicLink -Path (Join-Path $linkedBackupRoot "000001.bak") -Target $outsideFile | Out-Null
    $linkedBackupJournal = [ordered]@{
        version = 1
        backup_directory = $linkedBackupDirectoryName
        manifest_existed = $false
        entries = @(@{ path = "code-audit\\SKILL.md"; existed = $true; backup = "000001.bak" })
    } | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath (Join-Path $targetRoot ".personal-ai-library-transaction.json") -Value $linkedBackupJournal -Encoding UTF8
    $linkedBackupRejected = $false
    try {
        & $installer -TargetRoot $targetRoot
    }
    catch {
        if ($_.Exception.Message -match "Refusing to restore from a linked transaction file backup") {
            $linkedBackupRejected = $true
        }
        else {
            throw
        }
    }
    if (-not $linkedBackupRejected) {
        throw "Installer followed a linked transaction backup file."
    }
    if ((Get-Content -LiteralPath $skillFile -Raw) -notmatch "preserve installed file") {
        throw "Installer changed the destination while rejecting a linked backup."
    }
    Remove-Item -LiteralPath (Join-Path $targetRoot ".personal-ai-library-transaction.json") -Force
    Remove-Item -LiteralPath $linkedBackupRoot -Recurse -Force

    # A malicious manifest path must stop the installer before touching outside files.
    Set-Content -LiteralPath $outsideFile -Value "must remain" -Encoding UTF8
    $maliciousManifest = [ordered]@{
        version = 1
        files = @{ "..\Personal-AI-Library-outside-test.txt" = ("0" * 64) }
    } | ConvertTo-Json -Depth 5
    Set-Content -LiteralPath $manifestPath -Value $maliciousManifest -Encoding UTF8

    $rejected = $false
    try {
        & $installer -Force -TargetRoot $targetRoot
    }
    catch {
        $rejected = $true
    }

    if (-not $rejected) {
        throw "Installer accepted a path-traversal entry in its manifest."
    }
    if ((Get-Content -LiteralPath $outsideFile -Raw) -notmatch "must remain") {
        throw "Installer modified a file outside the installation folder."
    }

    # Windows alternate data streams and reserved device names are not
    # valid managed Skill paths, even when they remain under TargetRoot.
    foreach ($invalidPath in @("code-audit\SKILL.md:payload", "code-audit\NUL.txt")) {
        $specialPathManifest = [ordered]@{
            version = 1
            files = @{ $invalidPath = ("0" * 64) }
        } | ConvertTo-Json -Depth 5
        Set-Content -LiteralPath $manifestPath -Value $specialPathManifest -Encoding UTF8

        $specialPathRejected = $false
        try {
            & $installer -Force -TargetRoot $targetRoot
        }
        catch {
            if ($_.Exception.Message -match "Invalid Windows path component|Reserved Windows device name") {
                $specialPathRejected = $true
            }
            else {
                throw
            }
        }
        if (-not $specialPathRejected) {
            throw "Installer accepted an invalid Windows path component: $invalidPath"
        }
    }

    Write-Host "Installer tests passed: copy, reinstall, user-file preservation, force-update, stale-file cleanup, interrupted-update recovery, concurrent-run locking and manifest path validation."
}
finally {
    if (Test-Path -LiteralPath $sourceLinkedDir) {
        Remove-Item -LiteralPath $sourceLinkedDir -Force
    }
    if (Test-Path -LiteralPath $sourceLinkTarget) {
        Remove-Item -LiteralPath $sourceLinkTarget -Recurse -Force
    }
    if (Test-Path -LiteralPath $invalidSourceDir) {
        Remove-Item -LiteralPath $invalidSourceDir -Recurse -Force
    }
    if (Test-Path -LiteralPath $targetRoot) {
        Remove-Item -LiteralPath $targetRoot -Recurse -Force
    }
    if (Test-Path -LiteralPath $outsideFile) {
        Remove-Item -LiteralPath $outsideFile -Force
    }
    if (Test-Path -LiteralPath $linkedParent) {
        Remove-Item -LiteralPath $linkedParent -Force
    }
    if (Test-Path -LiteralPath $realParent) {
        Remove-Item -LiteralPath $realParent -Recurse -Force
    }
    if (Test-Path -LiteralPath $rollbackRoot) {
        Remove-Item -LiteralPath $rollbackRoot -Recurse -Force
    }
}
