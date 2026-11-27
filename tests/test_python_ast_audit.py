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
            (project / "main.py").write_text("import os\nimport pkg.helper\n", encoding="utf-8")
            code, report = self.run_audit(project)
            self.assertEqual(code, 0)
            self.assertEqual(report["unresolved_import_candidates"], 0)
            self.assertEqual(report["syntax_errors"], 0)

    def test_detects_missing_submodule_in_from_import_without_flagging_exports(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            package = project / "pkg"
            package.mkdir()
            (package / "__init__.py").write_text("VALUE = 1\n", encoding="utf-8")
            (package / "helper.py").write_text("VALUE = 2\n", encoding="utf-8")
            (project / "main.py").write_text(
                "from pkg import missing, helper, VALUE\n", encoding="utf-8"
            )
            code, report = self.run_audit(project)
            self.assertEqual(code, 0)
            candidates = [
                item["module"] for item in report["findings"]
                if item["kind"] == "unresolved_import_candidate"
            ]
            self.assertEqual(candidates, ["pkg.missing"])

    def test_local_module_takes_precedence_over_stdlib_name(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            (project / "json.py").write_text("VALUE = 1\n", encoding="utf-8")
            (project / "main.py").write_text("import json\n", encoding="utf-8")
            code, report = self.run_audit(project)
            self.assertEqual(code, 0)
            self.assertEqual(report["unresolved_import_candidates"], 0)

    def test_accepts_namespace_packages_without_init_files(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            namespace = project / "vendor" / "tools"
            namespace.mkdir(parents=True)
            (namespace / "helper.py").write_text("VALUE = 1\n", encoding="utf-8")
            (project / "main.py").write_text("import vendor.tools.helper\n", encoding="utf-8")
            code, report = self.run_audit(project)
            self.assertEqual(code, 0)
            self.assertEqual(report["unresolved_import_candidates"], 0)

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

    def test_detects_dynamic_code_and_process_execution(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            (project / "main.py").write_text(
                "eval(user_input)\nexec(source)\n"
                "import subprocess\nsubprocess.run(['tool'])\n"
                "import os\nos.system('echo ok')\n",
                encoding="utf-8",
            )
            code, report = self.run_audit(project)
            kinds = [item["kind"] for item in report["findings"]]
            self.assertEqual(code, 0)
            self.assertEqual(kinds.count("dynamic_code_candidate"), 2)
            self.assertEqual(kinds.count("process_execution_candidate"), 2)

    def test_detects_file_mutations_but_does_not_flag_read_only_open(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            (project / "main.py").write_text(
                "open('input.txt', 'r')\n"
                "open('output.txt', 'w')\n"
                "from pathlib import Path\n"
                "Path('old.txt').unlink()\n"
                "Path('out.txt').write_text('x')\n",
                encoding="utf-8",
            )
            code, report = self.run_audit(project)
            mutations = [
                item for item in report["findings"]
                if item["kind"] == "filesystem_mutation_candidate"
            ]
            self.assertEqual(code, 0)
            self.assertEqual(len(mutations), 3)


    def test_detects_keyword_write_modes_path_mutations_and_os_open(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            (project / "main.py").write_text(
                "import os\\nimport shutil\\n"
                "open('out.txt', mode='w')\\n"
                "open('in.txt', mode='r')\\n"
                "from pathlib import Path\\n"
                "Path('append.txt').open(mode='a')\\n"
                "Path('default-read.txt').open()\\n"
                "Path.open(Path('class-open.txt'), 'x')\\n"
                "Path('folder').mkdir()\\n"
                "shutil.move('old.txt', 'new.txt')\\n"
                "os.open('created.txt', os.O_WRONLY | os.O_CREAT, 0o600)\\n",
                encoding="utf-8",
            )
            code, report = self.run_audit(project)
            kinds = [item["kind"] for item in report["findings"]]
            self.assertEqual(code, 0)
            self.assertEqual(kinds.count("filesystem_mutation_candidate"), 5)
            self.assertEqual(kinds.count("filesystem_access_candidate"), 1)

    def test_detects_bare_and_swallowed_exceptions(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            (project / "main.py").write_text(
                "try:\n    work()\nexcept:\n    pass\n"
                "try:\n    work()\nexcept Exception:\n    return_value = None\n"
                "try:\n    work()\nexcept Exception:\n    logger.exception('failed')\n"
                "try:\n    work()\nexcept Exception:\n    raise\n",
                encoding="utf-8",
            )
            code, report = self.run_audit(project)
            kinds = [item["kind"] for item in report["findings"]]
            self.assertEqual(code, 0)
            self.assertEqual(kinds.count("bare_except_candidate"), 1)
            self.assertEqual(kinds.count("swallowed_exception_candidate"), 1)

    def test_does_not_scan_strings_or_comments_for_call_names(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            (project / "main.py").write_text(
                "# eval(secret) and os.system('bad')\n"
                "message = \"exec(code) subprocess.run(['x'])\"\n"
                "def safe(value):\n    return value + 1\n",
                encoding="utf-8",
            )
            code, report = self.run_audit(project)
            self.assertEqual(code, 0)
            self.assertEqual(report["security_review_candidates"], 0)

    def test_review_candidates_do_not_fail_audit_exit_status(self):
        with tempfile.TemporaryDirectory() as temp:
            project = Path(temp)
            (project / "main.py").write_text("eval(data)\n", encoding="utf-8")
            code, report = self.run_audit(project)
            self.assertEqual(code, 0)
            self.assertEqual(report["security_review_candidates"], 1)
            self.assertEqual(report["syntax_errors"], 0)


if __name__ == "__main__":
    unittest.main()
