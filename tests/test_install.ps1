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

    # Simulate interruption before the first manifest is written: complete
    # copied files must be adopted, and missing files must be restored.
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

    # Simulate an interrupted install: a managed file is missing while the
    # existing user-modified file must remain untouched on the recovery run.
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

    # Simulate a process interruption after the first committed file mutation.
    $interrupted = $false
    try {
        & (Join-Path $versionB "install.ps1") -Force -TargetRoot $rollbackTarget -TestFailAfterMutation 1
    }
    catch {
        $interrupted = $true
    }
    if (-not $interrupted) {
        throw "The installer failpoint did not interrupt the update."
    }
    $transactionJournal = Join-Path $rollbackTarget ".personal-ai-library-transaction\journal.json"
    if (-not (Test-Path -LiteralPath $transactionJournal -PathType Leaf)) {
        throw "An interrupted update did not retain its recovery journal."
    }

    # The next invocation must restore the pre-update state, then complete B.
    & (Join-Path $versionB "install.ps1") -Force -TargetRoot $rollbackTarget
    if ((Get-Content -LiteralPath (Join-Path $rollbackTarget "sample-skill\SKILL.md") -Raw).Trim() -ne "version B") {
        throw "The installer did not recover and complete the interrupted update."
    }
    if (Test-Path -LiteralPath (Join-Path $rollbackTarget ".personal-ai-library-transaction")) {
        throw "A completed transaction left recovery data behind."
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

    Write-Host "Installer tests passed: copy, interrupted-install recovery, user-file preservation, force-update, safe stale-file cleanup and manifest path validation."
}
finally {
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
