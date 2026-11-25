import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
AUDIT_SCRIPT = REPO_ROOT / "skills" / "code-audit" / "scripts" / "python_ast_audit.py"


class PythonAstAuditTests(unittest.TestCase):
    def run_audit(self, project: Path):
        result = subprocess.run(
            [sys.executable, str(AUDIT_SCRIPT), str(project), "--json"],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertTrue(result.stdout, result.stderr)
        return result.returncode, json.loads(result.stdout)

    def test_detects_missing_nested_module(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            (project / "pkg").mkdir()
            (project / "pkg" / "__init__.py").write_text("", encoding="utf-8")
            (project / "main.py").write_text("import pkg.missing\n", encoding="utf-8")

            code, report = self.run_audit(project)

            self.assertEqual(code, 0)
            candidates = [
                item["module"] for item in report["findings"]
                if item["kind"] == "unresolved_import_candidate"
            ]
            self.assertEqual(candidates, ["pkg.missing"])

    def test_accepts_existing_nested_module_and_stdlib(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            package = project / "pkg"
            package.mkdir()
            (package / "__init__.py").write_text("", encoding="utf-8")
            (package / "helper.py").write_text("VALUE = 1\n", encoding="utf-8")
            (project / "main.py").write_text(
                "import os\nimport pkg.helper\n", encoding="utf-8"
            )

            code, report = self.run_audit(project)

            self.assertEqual(code, 0)
            self.assertEqual(report["unresolved_import_candidates"], 0)
            self.assertEqual(report["syntax_errors"], 0)

    def test_detects_missing_submodule_in_from_import_without_flagging_exports(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            package = project / "pkg"
            package.mkdir()
            (package / "__init__.py").write_text(
                "VALUE = 1\\n", encoding="utf-8"
            )
            (package / "helper.py").write_text("VALUE = 2\\n", encoding="utf-8")
            (project / "main.py").write_text(
                "from pkg import missing, helper, VALUE\\n", encoding="utf-8"
            )

            code, report = self.run_audit(project)

            self.assertEqual(code, 0)
            candidates = [
                item["module"] for item in report["findings"]
                if item["kind"] == "unresolved_import_candidate"
            ]
            self.assertEqual(candidates, ["pkg.missing"])

    def test_reports_syntax_error_and_skips_virtual_environment(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            (project / "broken.py").write_text("def broken(:\n", encoding="utf-8")
            venv = project / ".venv"
            venv.mkdir()
            (venv / "ignored.py").write_text("not valid python !!!\n", encoding="utf-8")

            code, report = self.run_audit(project)

            self.assertEqual(code, 1)
            self.assertEqual(report["python_files"], 1)
            self.assertEqual(report["syntax_errors"], 1)
            self.assertEqual(report["read_errors"], 0)


if __name__ == "__main__":
    unittest.main()
