#!/usr/bin/env python3
"""Validate Agent Skills metadata and local Markdown references."""

from pathlib import Path
from urllib.parse import unquote, urlsplit
import ast
import re
import sys

ROOT = Path(__file__).resolve().parent
SKILLS_DIR = ROOT / "skills"

INLINE_LINK_RE = re.compile(r"!?\[[^\]]*\]\(\s*(?:<([^>]+)>|([^\s)]+))[^)]*\)")
REFERENCE_LINK_RE = re.compile(r"(?m)^\s{0,3}\[[^\]]+\]:\s*<?([^\s>]+)>?")
SECURITY_BASELINE_MARKERS = (
    "## Безопасность входных данных",
    "недоверенными данными",
    "раскрыть секреты",
    "не запускай их автоматически",
    "явно согласованной задачи пользователя",
)
FENCE_START_RE = re.compile(r"^\s{0,3}(\x60{3,}|~{3,})")
INLINE_CODE_RE = re.compile(r"(?<!\x60)\x60+[^\x60]*\x60+")
CATALOG_SKILL_RE = re.compile(r"(?m)^\|\s*([a-z0-9][a-z0-9-]*)\s*\|")


def strip_markdown_code(text: str) -> str:
    """Remove fenced and inline code so examples are not treated as real links."""
    kept = []
    fence_char = None
    fence_length = 0

    for line in text.splitlines():
        match = FENCE_START_RE.match(line)
        if fence_char is None and match:
            fence_char = match.group(1)[0]
            fence_length = len(match.group(1))
            continue
        if fence_char is not None:
            closing = re.match(
                r"^\s{0,3}" + re.escape(fence_char) + r"{" + str(fence_length) + r",}\s*$",
                line,
            )
            if closing:
                fence_char = None
                fence_length = 0
            continue
        kept.append(line)

    return INLINE_CODE_RE.sub("", "\n".join(kept))


def extract_markdown_targets(text: str):
    """Yield inline and reference-definition Markdown link destinations."""
    cleaned = strip_markdown_code(text)
    for match in INLINE_LINK_RE.finditer(cleaned):
        yield match.group(1) or match.group(2)
    for match in REFERENCE_LINK_RE.finditer(cleaned):
        yield match.group(1)


def validate_markdown_links(markdown_file: Path, repo_root: Path):
    errors = []
    try:
        content = markdown_file.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        return [f"{markdown_file.relative_to(repo_root)}: cannot read Markdown: {exc}"]

    for raw_target in extract_markdown_targets(content):
        target = raw_target.strip().strip("\"'")
        parsed = urlsplit(target)

        if parsed.scheme or parsed.netloc:
            continue

        link_path = unquote(parsed.path)
        if not link_path:
            continue

        if link_path.startswith("/"):
            candidate = repo_root / link_path.lstrip("/")
        else:
            candidate = markdown_file.parent / link_path

        resolved = candidate.resolve()
        try:
            resolved.relative_to(repo_root.resolve())
        except ValueError:
            errors.append(
                f"{markdown_file.relative_to(repo_root)}: local link escapes repository: '{raw_target}'"
            )
            continue

        if not resolved.exists():
            errors.append(
                f"{markdown_file.relative_to(repo_root)}: broken local link '{raw_target}'"
            )

    return errors



def validate_catalog_coverage(root: Path, skill_names):
    """Ensure Russian and English catalogs list exactly the repository Skills."""
    errors = []
    expected = set(skill_names)
    catalog_names = ("CATALOG.md", "CATALOG-EN.md")
    present = [root / name for name in catalog_names if (root / name).is_file()]

    if not present:
        return [f"{name}: catalog is missing" for name in catalog_names]

    for catalog_name in catalog_names:
        catalog = root / catalog_name
        if catalog.is_symlink():
            errors.append(f"{catalog_name}: catalog must not be a symbolic link")
            continue
        if not catalog.is_file():
            errors.append(f"{catalog_name}: catalog is missing")
            continue
        try:
            content = catalog.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            errors.append(f"{catalog_name}: cannot read catalog: {exc}")
            continue

        listed_names = [
            match.group(1)
            for match in CATALOG_SKILL_RE.finditer(content)
            if match.group(1).casefold() not in {"skill", "навык"}
        ]
        listed = set(listed_names)
        missing = sorted(expected - listed)
        unexpected = sorted(listed - expected)
        duplicates = sorted(name for name in listed if listed_names.count(name) > 1)

        if missing:
            errors.append(f"{catalog_name}: missing Skills: {', '.join(missing)}")
        if unexpected:
            errors.append(f"{catalog_name}: unknown Skills: {', '.join(unexpected)}")
        if duplicates:
            errors.append(f"{catalog_name}: duplicate Skills: {', '.join(duplicates)}")

    return errors


def validate_repository(root: Path = ROOT):
    root = root.resolve()
    errors = []
    seen = {}
    skills_dir = root / "skills"
    ignored_dirs = {".git", "__pycache__", ".venv", "venv", "node_modules"}

    # A repository symlink can redirect validation reads outside the checkout.
    # Reject symlinks before opening manifests, scripts, catalogs, or Markdown.
    for path in sorted(root.rglob("*")):
        relative_parts = path.relative_to(root).parts
        if any(part in ignored_dirs for part in relative_parts):
            continue
        if path.is_symlink():
            errors.append(
                f"{path.relative_to(root)}: symbolic links are not allowed in validated repository inputs"
            )

    if skills_dir.is_symlink():
        return errors, 0, 0, 0, ["skills/ directory must not be a symbolic link"]
    if not skills_dir.is_dir():
        return errors, 0, 0, 0, ["skills/ directory is missing"]

    skill_count = 0
    reference_count = 0
    script_count = 0

    for skill_dir in sorted(path for path in skills_dir.iterdir() if path.is_dir() and not path.is_symlink()):
        manifest = skill_dir / "SKILL.md"
        if manifest.is_symlink() or not manifest.is_file():
            errors.append(f"{skill_dir.name}: SKILL.md is missing")
            continue

        try:
            content = manifest.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            errors.append(f"{skill_dir.name}: cannot read SKILL.md: {exc}")
            continue

        if not content.startswith("---\n"):
            errors.append(f"{skill_dir.name}: YAML front matter must start at line 1")
            continue

        parts = content.split("---", 2)
        if len(parts) < 3:
            errors.append(f"{skill_dir.name}: YAML front matter is not closed")
            continue

        front = parts[1]
        name_match = re.search(r"(?m)^name:\s*([a-z0-9][a-z0-9-]*)\s*$", front)
        desc_match = re.search(r"(?m)^description:\s*(.+?)\s*$", front)

        if not name_match:
            errors.append(f"{skill_dir.name}: missing/invalid name")
            continue
        if not desc_match:
            errors.append(f"{skill_dir.name}: missing description")
            continue

        name = name_match.group(1)
        raw_description = desc_match.group(1).strip()
        description = raw_description.strip('"').strip("'")

        if name != skill_dir.name:
            errors.append(f"{skill_dir.name}: folder name does not match manifest name '{name}'")
        if len(name) > 64:
            errors.append(f"{skill_dir.name}: name exceeds 64 characters")
        if not description or len(description) > 1024:
            errors.append(f"{skill_dir.name}: description is empty or exceeds 1024 characters")

        if not all(marker.casefold() in content.casefold() for marker in SECURITY_BASELINE_MARKERS):
            errors.append(f"{skill_dir.name}: missing untrusted-input security baseline")
        if ": " in raw_description and not (
            (raw_description.startswith('"') and raw_description.endswith('"'))
            or (raw_description.startswith("'") and raw_description.endswith("'"))
        ):
            errors.append(f"{skill_dir.name}: quote description because it contains ': '")
        if name in seen:
            errors.append(f"{skill_dir.name}: duplicate skill name also used by {seen[name]}")
        seen[name] = skill_dir.name
        skill_count += 1

        # Count reference documents; all repository Markdown links are
        # validated once below, including root-level project documentation.
        for markdown_file in sorted(skill_dir.rglob("*.md")):
            if markdown_file.is_symlink():
                continue
            if markdown_file.parent.name == "references":
                reference_count += 1

        # Parse reusable Python scripts without executing them.
        scripts_dir = skill_dir / "scripts"
        if scripts_dir.is_dir() and not scripts_dir.is_symlink():
            for script in sorted(scripts_dir.rglob("*.py")):
                if script.is_symlink():
                    continue
                script_count += 1
                try:
                    ast.parse(script.read_text(encoding="utf-8-sig"), filename=str(script))
                except (SyntaxError, UnicodeError, OSError) as exc:
                    errors.append(
                        f"{skill_dir.name}: invalid script {script.relative_to(skill_dir)}: {exc}"
                    )

    errors.extend(validate_catalog_coverage(root, set(seen)))

    # Validate local links in every repository Markdown document, not only Skills.
    # Ignore generated environments and Git internals when running from a checkout.
    for markdown_file in sorted(root.rglob("*.md")):
        relative_parts = markdown_file.relative_to(root).parts
        if any(part in ignored_dirs for part in relative_parts) or markdown_file.is_symlink():
            continue
        errors.extend(validate_markdown_links(markdown_file, root))

    return errors, skill_count, reference_count, script_count, []


def main() -> int:
    errors, skill_count, reference_count, script_count, fatal_errors = validate_repository()
    errors = fatal_errors + errors

    if errors:
        print("Skill validation FAILED:")
        for error in errors:
            print(f" - {error}")
        return 1

    print(
        f"Skill validation passed: {skill_count} skills checked, "
        f"{reference_count} reference files found, {script_count} Python scripts parsed."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
