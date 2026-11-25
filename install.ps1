param(
    [switch]$Force,
    [string]$TargetRoot = (Join-Path $HOME ".agents\skills")
)

$ErrorActionPreference = "Stop"

$sourceRoot = Join-Path $PSScriptRoot "skills"
$targetRoot = $TargetRoot

if (-not (Test-Path $sourceRoot)) {
    throw "Skills folder not found: $sourceRoot"
}

New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null

$skillFolders = Get-ChildItem -Path $sourceRoot -Directory
if (-not $skillFolders) {
    Write-Host "No skills found to install."
    exit 0
}

foreach ($folder in $skillFolders) {
    $sourceSkill = Join-Path $folder.FullName "SKILL.md"
    if (-not (Test-Path $sourceSkill)) {
        Write-Warning "Skipping $($folder.Name): SKILL.md is missing"
        continue
    }

    $targetSkillDir = Join-Path $targetRoot $folder.Name

    if ((Test-Path $targetSkillDir) -and -not $Force) {
        Write-Host "Already exists, skipping: $($folder.Name) (use -Force to update)"
        continue
    }

    # Copy into the skills root. With -Force, matching files are updated,
    # while unrelated user files in the destination skill folder are preserved.
    Copy-Item -LiteralPath $folder.FullName -Destination $targetRoot -Recurse -Force
    Write-Host "Installed/updated: $($folder.Name)"
}

Write-Host ""
Write-Host "Done. Codex skills folder: $targetRoot"
Write-Host "Restart Codex if it is already running."
