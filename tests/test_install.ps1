$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $repoRoot "install.ps1"
$targetRoot = Join-Path $env:TEMP ("Personal-AI-Library-Test-" + [guid]::NewGuid().ToString("N"))

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

    $localFile = Join-Path $targetRoot "code-audit\user-local-note.txt"
    Set-Content -LiteralPath $localFile -Value "keep me" -Encoding UTF8
    Set-Content -LiteralPath $skillFile -Value "local modified copy" -Encoding UTF8

    & $installer -TargetRoot $targetRoot
    if ((Get-Content -LiteralPath $skillFile -Raw) -notmatch "local modified copy") {
        throw "Without -Force, existing skill files should remain unchanged."
    }

    & $installer -Force -TargetRoot $targetRoot
    if (-not (Test-Path -LiteralPath $localFile -PathType Leaf)) {
        throw "Force update removed a user-created file."
    }

    $sourceSkill = Join-Path $repoRoot "skills\code-audit\SKILL.md"
    if ((Get-Content -LiteralPath $skillFile -Raw) -ne (Get-Content -LiteralPath $sourceSkill -Raw)) {
        throw "Force update did not replace the skill with the repository version."
    }

    Write-Host "Installer tests passed: initial copy, recursive files, skip-existing and force-update preservation."
}
finally {
    if (Test-Path -LiteralPath $targetRoot) {
        Remove-Item -LiteralPath $targetRoot -Recurse -Force
    }
}
