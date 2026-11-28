#!/usr/bin/env python3
"""Read-only Python AST audit: syntax, imports and review candidates. Never executes project code."""
from __future__ import annotations

import argparse
import ast
import json
import os
import stat
import sys
import sysconfig
from collections import Counter
from pathlib import Path

STDLIB_ROOT = Path(sysconfig.get_paths()["stdlib"]).resolve()
STDLIB_NAMES = set(getattr(sys, "stdlib_module_names", ()))

SKIP_DIRS = {
    ".git", ".hg", ".svn", ".venv", "venv", "env", "__pycache__",
    "site-packages", "dist", "build", ".tox", ".mypy_cache", ".pytest_cache",
}


def is_stdlib_module(name: str) -> bool:
    top = name.split(".", 1)[0]
    if top in STDLIB_NAMES or top in sys.builtin_module_names:
        return True
    if (STDLIB_ROOT / (top + ".py")).is_file():
        return True
    module_path = STDLIB_ROOT / top
    if (module_path / "__init__.py").is_file():
        return True
    platform_stdlib = Path(sysconfig.get_paths().get("platstdlib", str(STDLIB_ROOT)))
    extension_dir = platform_stdlib / "lib-dynload"
    return extension_dir.is_dir() and any(extension_dir.glob(top + ".*"))


def is_reparse_point(path: Path) -> bool:
    """Return True for symlinks and Windows junction/reparse points."""
    try:
        info = path.lstat()
    except OSError:
        return path.is_symlink()
    reparse_flag = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)
    return path.is_symlink() or bool(
        getattr(info, "st_file_attributes", 0) & reparse_flag
    )


def has_symlink_component(root: Path, path: Path) -> bool:
    """Return True when a path or any component below root is a reparse point."""
    try:
        relative = path.relative_to(root)
    except ValueError:
        return True

    current = root
    if is_reparse_point(current):
        return True
    for part in relative.parts:
        current = current / part
        if is_reparse_point(current):
            return True
    return False


def iter_python_files(root: Path):
    """Walk the project without descending into symlinks or Windows junctions."""
    pending = [root]
    while pending:
        directory = pending.pop()
        try:
            with os.scandir(directory) as scan:
                entries = sorted(scan, key=lambda entry: entry.name)
        except OSError:
            continue

        for entry in entries:
            path = Path(entry.path)
            relative = path.relative_to(root)
            if any(part in SKIP_DIRS for part in relative.parts):
                continue
            if is_reparse_point(path):
                continue
            if entry.is_dir(follow_symlinks=False):
                pending.append(path)
            elif path.suffix == ".py" and entry.is_file(follow_symlinks=False):
                yield path


def local_module_exists(root: Path, module: str) -> bool:
    parts = module.split(".")
    base = root.joinpath(*parts)
    module_file = base.with_suffix(".py")
    return (
        (not has_symlink_component(root, module_file) and module_file.is_file())
        or (not has_symlink_component(root, base) and base.is_dir())
    )


def package_export_names(root: Path, module: str):
    init_file = root.joinpath(*module.split(".")) / "__init__.py"
    if has_symlink_component(root, init_file) or not init_file.is_file():
        return set()
    try:
        tree = ast.parse(init_file.read_text(encoding="utf-8-sig"), filename=str(init_file))
    except (OSError, UnicodeError, SyntaxError):
        return set()
    names = set()
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            names.add(node.name)
        elif isinstance(node, (ast.Import, ast.ImportFrom)):
            for alias in node.names:
                names.add(alias.asname or alias.name.split(".")[0])
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                for child in ast.walk(target):
                    if isinstance(child, ast.Name):
                        names.add(child.id)
        if isinstance(node, ast.Assign):
            for target in node.targets:
                if isinstance(target, ast.Name) and target.id == "__all__" and isinstance(node.value, (ast.List, ast.Tuple)):
                    names.update(
                        item.value for item in node.value.elts
                        if isinstance(item, ast.Constant) and isinstance(item.value, str)
                    )
    return names


def dotted_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = dotted_name(node.value)
        return prefix + "." + node.attr if prefix else node.attr
    return ""


def handler_has_raise_or_logging(handler: ast.ExceptHandler) -> bool:
    """Inspect this handler but do not count code nested in a new scope."""
    stack = list(handler.body)
    while stack:
        node = stack.pop()
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)):
            continue
        if isinstance(node, ast.Raise):
            return True
        if isinstance(node, ast.Call):
            name = dotted_name(node.func)
            if (
                name.startswith("logging.")
                or name.startswith("logger.")
                or name.startswith("log.")
                or name in {"warning", "error", "exception", "critical"}
            ):
                return True
        stack.extend(ast.iter_child_nodes(node))
    return False


def keyword_value(node: ast.Call, keyword_name: str):
    for keyword in node.keywords:
        if keyword.arg == keyword_name:
            return keyword.value
    return None


def is_path_constructor(node: ast.AST) -> bool:
    return (
        isinstance(node, ast.Call)
        and dotted_name(node.func) in {"Path", "pathlib.Path"}
    )


def is_write_mode(node: ast.AST | None) -> bool:
    return (
        isinstance(node, ast.Constant)
        and isinstance(node.value, str)
        and any(flag in node.value for flag in "wax+")
    )


class ReviewVisitor(ast.NodeVisitor):
    """Emit conservative review candidates; findings are not vulnerability verdicts."""

    PROCESS_CALLS = {
        "subprocess.run", "subprocess.Popen", "subprocess.call",
        "subprocess.check_call", "subprocess.check_output",
        "os.system", "os.popen", "os.popen2", "os.popen3", "os.popen4",
    }
    FILE_MUTATION_CALLS = {
        "os.remove", "os.unlink", "os.rmdir", "os.rename", "os.replace",
        "os.mkdir", "os.makedirs", "os.chmod", "os.chown", "os.truncate",
        "os.utime", "os.symlink", "os.link",
        "shutil.rmtree", "shutil.move", "shutil.copy", "shutil.copy2",
        "shutil.copyfile", "shutil.copytree",
        "Path.unlink", "Path.rmdir", "Path.write_text", "Path.write_bytes",
        "Path.touch", "Path.mkdir", "Path.rename", "Path.replace",
        "Path.chmod", "Path.symlink_to", "Path.hardlink_to",
    }

    def __init__(self, rel: str):
        self.rel = rel
        self.findings = []

    def add(self, kind: str, node: ast.AST, message: str):
        self.findings.append({
            "kind": kind,
            "file": self.rel,
            "line": getattr(node, "lineno", None),
            "severity": "review",
            "message": message,
        })

    def visit_Call(self, node: ast.Call):
        name = dotted_name(node.func)
        path_instance_open = False
        if isinstance(node.func, ast.Attribute):
            if node.func.attr == "open" and is_path_constructor(node.func.value):
                path_instance_open = True
            elif (
                node.func.attr in {
                    "unlink", "rmdir", "write_text", "write_bytes", "touch",
                    "mkdir", "rename", "replace", "chmod", "symlink_to",
                    "hardlink_to",
                }
                and is_path_constructor(node.func.value)
            ):
                name = "Path." + node.func.attr

        if name in {"eval", "exec", "builtins.eval", "builtins.exec"}:
            self.add(
                "dynamic_code_candidate", node,
                f"Вызов {name} динамически исполняет код; проверьте источник и валидацию данных.",
            )
        elif name == "compile":
            self.add(
                "dynamic_code_candidate", node,
                "Вызов compile создаёт code object; проверьте, где и как он затем исполняется.",
            )
        elif name in self.PROCESS_CALLS:
            self.add(
                "process_execution_candidate", node,
                f"Вызов {name} запускает внешний процесс или команду; проверьте аргументы и доверие к данным.",
            )
        elif name in self.FILE_MUTATION_CALLS:
            self.add(
                "filesystem_mutation_candidate", node,
                f"Вызов {name} изменяет или удаляет файлы; проверьте пути, права и ожидаемость операции.",
            )
        elif path_instance_open or name in {"Path.open", "pathlib.Path.open"}:
            if path_instance_open:
                mode = node.args[0] if node.args else keyword_value(node, "mode")
            else:
                mode = node.args[1] if len(node.args) > 1 else keyword_value(node, "mode")
            if is_write_mode(mode):
                self.add(
                    "filesystem_mutation_candidate", node,
                    "Path.open() открыт в режиме записи/добавления; проверьте путь и ожидаемость изменения файла.",
                )
        elif name in {"open", "io.open", "builtins.open"}:
            mode = node.args[1] if len(node.args) > 1 else keyword_value(node, "mode")
            if is_write_mode(mode):
                self.add(
                    "filesystem_mutation_candidate", node,
                    "open() открыт в режиме записи/добавления; проверьте путь и ожидаемость изменения файла.",
                )
        elif name == "os.open":
            self.add(
                "filesystem_access_candidate", node,
                "Вызов os.open открывает файловый дескриптор; проверьте флаги записи, создания и усечения файла.",
            )
        self.generic_visit(node)

    def visit_ExceptHandler(self, node: ast.ExceptHandler):
        if node.type is None:
            self.add(
                "bare_except_candidate", node,
                "Bare except перехватывает почти все исключения, включая системные; проверьте необходимость.",
            )
        elif isinstance(node.type, ast.Name) and node.type.id in {"Exception", "BaseException"}:
            if not handler_has_raise_or_logging(node):
                self.add(
                    "swallowed_exception_candidate", node,
                    f"Обработчик {node.type.id} не содержит явного повторного raise или логирования; исключение может теряться.",
                )
        self.generic_visit(node)


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
    visitor = ReviewVisitor(rel)
    visitor.visit(tree)
    findings.extend(visitor.findings)

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            modules = [(alias.name, node.lineno) for alias in node.names]
        elif isinstance(node, ast.ImportFrom):
            if node.level or not node.module:
                continue
            module = node.module
            if local_module_exists(root, module):
                package_dir = root.joinpath(*module.split("."))
                if package_dir.is_dir():
                    exported = package_export_names(root, module)
                    for alias in node.names:
                        if alias.name == "*" or alias.name in exported:
                            continue
                        if local_module_exists(root, module + "." + alias.name):
                            continue
                        findings.append({
                            "kind": "unresolved_import_candidate",
                            "file": rel,
                            "line": node.lineno,
                            "module": module + "." + alias.name,
                            "severity": "review",
                            "message": "Подмодуль не найден, но имя может экспортироваться динамически; проверьте __init__.py вручную.",
                        })
                continue
            findings.append({
                "kind": "unresolved_import_candidate",
                "file": rel,
                "line": node.lineno,
                "module": module,
                "severity": "review",
                "message": "Не найден как локальный модуль или stdlib; проверьте зависимости, namespace package и sys.path вручную.",
            })
            continue
        else:
            continue
        for module, line in modules:
            if not module or local_module_exists(root, module) or is_stdlib_module(module):
                continue
            findings.append({
                "kind": "unresolved_import_candidate",
                "file": rel,
                "line": line,
                "module": module,
                "severity": "review",
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

    counts = Counter(item["kind"] for item in findings)
    summary = {
        "root": str(root),
        "python_files": len(files),
        "syntax_errors": counts["syntax_error"],
        "read_errors": counts["read_error"],
        "unresolved_import_candidates": counts["unresolved_import_candidate"],
        "security_review_candidates": sum(
            count for kind, count in counts.items()
            if kind.endswith("_candidate") and kind != "unresolved_import_candidate"
        ),
        "finding_counts": dict(sorted(counts.items())),
        "findings": findings,
        "limitations": [
            "Скрипт не исполняет и не импортирует файлы проекта.",
            "Все *_candidate — сигналы для ручной проверки, а не доказанные ошибки или уязвимости.",
            "Проверяются прямые AST-вызовы и буквальные режимы записи; aliases, переменные Path, динамические mode/flags, getattr, reflection и обёртки могут быть пропущены.",
            "Не разрешаются динамические и относительные импорты, дополнительные sys.path и import hooks.",
            "Внешние зависимости нужно сверить с requirements/pyproject/lock-файлами.",
            "Запись/удаление файлов и запуск процессов сами по себе не являются вредоносными.",
        ],
    }
    if args.json:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
    else:
        print(f"Python files: {summary['python_files']}")
        print(f"Syntax errors: {summary['syntax_errors']}")
        print(f"Read errors: {summary['read_errors']}")
        print(f"Unresolved import candidates: {summary['unresolved_import_candidates']}")
        print(f"Security review candidates: {summary['security_review_candidates']}")
        for item in findings:
            location = item["file"]
            if item.get("line") is not None:
                location += f":{item['line']}"
            detail = item.get("module") or item.get("message", "")
            print(f"- [{item['kind']}] {location}: {detail}")
        print("NOTE: candidates require manual verification; they are not vulnerability verdicts.")
    return 1 if summary["syntax_errors"] or summary["read_errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
