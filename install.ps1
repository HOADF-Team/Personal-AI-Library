param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$sourceRoot = Join-Path $PSScriptRoot "skills"
$targetRoot = Join-Path $HOME ".agents\skills"

if (-not (Test-Path $sourceRoot)) {
    throw "Папка skills не найдена: $sourceRoot"
}

New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null

$skillFolders = Get-ChildItem -Path $sourceRoot -Directory
if (-not $skillFolders) {
    Write-Host "Навыки для установки не найдены."
    exit 0
}

foreach ($folder in $skillFolders) {
    $sourceSkill = Join-Path $folder.FullName "SKILL.md"
    if (-not (Test-Path $sourceSkill)) {
        Write-Warning "Пропуск $($folder.Name): отсутствует SKILL.md"
        continue
    }

    $targetSkillDir = Join-Path $targetRoot $folder.Name

    if ((Test-Path $targetSkillDir) -and -not $Force) {
        Write-Host "Уже существует, пропуск: $($folder.Name) (для обновления используйте -Force)"
        continue
    }

    if (Test-Path $targetSkillDir) {
        Remove-Item -LiteralPath $targetSkillDir -Recurse -Force
    }

    Copy-Item -LiteralPath $folder.FullName -Destination $targetSkillDir -Recurse
    Write-Host "Установлен: $($folder.Name)"
}

Write-Host ""
Write-Host "Готово. Папка навыков Codex: $targetRoot"
Write-Host "Если Codex уже запущен, перезапустите его для перечитывания навыков."
