#!/usr/bin/env python3
"""Validate Agent Skills metadata using only the Python standard library."""

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent
SKILLS_DIR = ROOT / "skills"
errors = []
seen = {}

if not SKILLS_DIR.is_dir():
    print("Skill validation FAILED: skills/ directory is missing.")
    sys.exit(1)

for skill_dir in sorted(p for p in SKILLS_DIR.iterdir() if p.is_dir()):
    manifest = skill_dir / "SKILL.md"
    if not manifest.is_file():
        errors.append(f"{skill_dir.name}: SKILL.md is missing")
        continue

    content = manifest.read_text(encoding="utf-8")
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
    if ": " in raw_description and not (
        (raw_description.startswith('"') and raw_description.endswith('"'))
        or (raw_description.startswith("'") and raw_description.endswith("'"))
    ):
        errors.append(f"{skill_dir.name}: quote description because it contains ': '")
    if name in seen:
        errors.append(f"{skill_dir.name}: duplicate skill name also used by {seen[name]}")
    seen[name] = skill_dir.name

if errors:
    print("Skill validation FAILED:")
    for error in errors:
        print(f" - {error}")
    sys.exit(1)

print(f"Skill validation passed: {len(seen)} skills checked.")
