import tempfile
import unittest
from pathlib import Path

from validate_skills import validate_markdown_links, validate_repository


class MarkdownLinkValidationTests(unittest.TestCase):
    def test_checks_reference_links_and_ignores_code_and_external_urls(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            skill_dir = root / "skills" / "demo"
            references = skill_dir / "references"
            references.mkdir(parents=True)
            (references / "existing.md").write_text("# Existing\n", encoding="utf-8")

            fence = chr(96) * 3
            tick = chr(96)
            document = references / "guide.md"
            document.write_text(
                "# Guide\n"
                "[valid](existing.md)\n"
                "[broken](missing.md)\n"
                "[external](https://example.com/page)\n"
                + fence + "markdown\n"
                + "[example](does-not-exist.md)\n"
                + fence + "\n"
                + "Inline example: " + tick + "[fake](also-missing.md)" + tick + "\n",
                encoding="utf-8",
            )

            errors = validate_markdown_links(document, root)
            self.assertEqual(len(errors), 1)
            self.assertIn("missing.md", errors[0])

    def test_rejects_local_links_that_escape_repository(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "repo"
            references = root / "skills" / "demo" / "references"
            references.mkdir(parents=True)
            document = references / "guide.md"
            document.write_text("[outside](../../../../outside.txt)\n", encoding="utf-8")

            errors = validate_markdown_links(document, root)
            self.assertEqual(len(errors), 1)
            self.assertIn("escapes repository", errors[0])

    def test_repository_validation_checks_reference_documents(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            skill_dir = root / "skills" / "demo"
            references = skill_dir / "references"
            references.mkdir(parents=True)
            (skill_dir / "SKILL.md").write_text(
                "---\nname: demo\ndescription: Example skill.\n---\n# Demo\n",
                encoding="utf-8",
            )
            (references / "guide.md").write_text(
                "# Guide\n[missing](not-here.md)\n",
                encoding="utf-8",
            )

            errors, skill_count, reference_count, script_count, fatal = validate_repository(root)

            self.assertEqual(fatal, [])
            self.assertEqual(skill_count, 1)
            self.assertEqual(reference_count, 1)
            self.assertEqual(script_count, 0)
            self.assertTrue(any("not-here.md" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
