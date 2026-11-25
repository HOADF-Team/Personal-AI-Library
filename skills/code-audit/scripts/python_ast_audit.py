#!/usr/bin/env python3
"""Read-only Python source audit: syntax, imports and basic structure. No project code is executed."""
from __future__ import annotations

import argparse
import ast
import json
import sys
import sysconfig
from pathlib import Path

STDLIB_ROOT = Path(sysconfig.get_paths()["stdlib"]).resolve()\nSTDLIB_NAMES = set(getattr(sys, "stdlib_module_names", ()))\n\n\ndef is_stdlib_module(name: str) -> bool:\n    top = name.split(".", 1)[0]\n    if top in STDLIB_NAMES or top in sys.builtin_module_names:\n        return True\n    # Python 3.9 has no sys.stdlib_module_names; use its stdlib directory.\n    return (STDLIB_ROOT / top).exists()\n\n\nSKIP_DIRS = {
    ".git", ".hg", ".svn", ".venv", "venv", "env", "__pycache__",
    "site-packages", "dist", "build", ".tox", ".mypy_cache", ".pytest_cache",
}


def iter_python_files(root: Path):
    for path in root.rglob("*.py"):
        if any(part in SKIP_DIRS for part in path.relative_to(root).parts):
            continue
        yield path


def local_module_exists(root: Path, module: str) -> bool:
    parts = module.split(".")
    base = root.joinpath(*parts)
    return base.with_suffix(".py").is_file() or (base / "__init__.py").is_file()


def audit_file(path: Path, root: Path):
    rel = path.relative_to(root).as_posix()
    try:
        source = path.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeError) as exc:
        return [{"kind": "read_error", "file": rel, "message": str(exc)}]

    try:
        tree = ast.parse(source, filename=rel)
    except SyntaxError as exc:
        return [{
            "kind": "syntax_error", "file": rel, "line": exc.lineno,
            "column": exc.offset, "message": exc.msg,
        }]

    findings = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules = [(alias.name, node.lineno) for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            if node.level:
                # Relative imports depend on package context; do not guess resolution.
                continue
            modules = [(node.module, node.lineno)] if node.module else []
        else:
            continue

        for module, line in modules:
            if not module:
                continue
            top = module.split(".", 1)[0]
            if is_stdlib_module(module):
                continue
            if local_module_exists(root, module):
                continue
            if local_module_exists(root, top):
                continue
            findings.append({
                "kind": "unresolved_import_candidate",
                "file": rel,
                "line": line,
                "module": module,
                "message": "Не найден как локальный модуль или stdlib; проверьте зависимости, namespace package и sys.path вручную.",
            })
    return findings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project", nargs="?", default=".", help="Корень проекта")
    parser.add_argument("--json", action="store_true", help="Вывести JSON")
    args = parser.parse_args()
    root = Path(args.project).resolve()
    if not root.is_dir():
        parser.error(f"Не каталог: {root}")

    files = sorted(iter_python_files(root))
    findings = []
    for path in files:
        findings.extend(audit_file(path, root))

    summary = {
        "root": str(root),
        "python_files": len(files),
        "syntax_errors": sum(x["kind"] == "syntax_error" for x in findings),
        "read_errors": sum(x["kind"] == "read_error" for x in findings),
        "unresolved_import_candidates": sum(
            x["kind"] == "unresolved_import_candidate" for x in findings
        ),
        "findings": findings,
        "limitations": [
            "Скрипт не исполняет и не импортирует файлы проекта.",
            "Кандидат на отсутствующий импорт не является доказанной ошибкой.",
            "Не разрешаются динамические импорты, относительные импорты и runtime sys.path.",
            "Внешние зависимости нужно сверить с requirements/pyproject/lock-файлами.",
        ],
    }
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print(f"Python files: {summary['python_files']}")
        print(f"Syntax errors: {summary['syntax_errors']}")
        print(f"Read errors: {summary['read_errors']}")
        print(f"Unresolved import candidates: {summary['unresolved_import_candidates']}")
        for item in findings:
            location = item["file"]
            if "line" in item:
                location += f":{item['line']}"
            detail = item.get("module") or item.get("message", "")
            print(f"- [{item['kind']}] {location}: {detail}")
        print("NOTE: unresolved imports require manual verification.")
    return 1 if summary["syntax_errors"] or summary["read_errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
