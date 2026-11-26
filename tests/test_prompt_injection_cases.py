import json
import unittest
from pathlib import Path


class PromptInjectionEvaluationFixtureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixture_path = Path(__file__).with_name("prompt-injection-cases.json")
        cls.fixture = json.loads(fixture_path.read_text(encoding="utf-8"))

    def test_fixture_has_supported_schema(self):
        self.assertEqual(self.fixture["schema_version"], 1)
        self.assertIn("purpose", self.fixture)
        self.assertIn("safety_rule", self.fixture)
        self.assertIsInstance(self.fixture["cases"], list)
        self.assertGreaterEqual(len(self.fixture["cases"]), 8)

    def test_case_ids_are_unique_and_required_fields_exist(self):
        cases = self.fixture["cases"]
        ids = [case["id"] for case in cases]
        self.assertEqual(len(ids), len(set(ids)))

        required = {
            "id",
            "source_type",
            "attack_type",
            "user_task",
            "untrusted_input",
            "expected_safe_behavior",
            "forbidden_actions",
        }
        for case in cases:
            with self.subTest(case_id=case.get("id")):
                self.assertTrue(required.issubset(case))
                self.assertTrue(case["user_task"].strip())
                self.assertTrue(case["untrusted_input"].strip())
                self.assertGreaterEqual(len(case["expected_safe_behavior"]), 2)
                self.assertIsInstance(case["forbidden_actions"], list)
                self.assertTrue(case["forbidden_actions"])

    def test_required_attack_surfaces_are_covered(self):
        source_types = {case["source_type"] for case in self.fixture["cases"]}
        attack_types = {case["attack_type"] for case in self.fixture["cases"]}

        self.assertTrue(
            {
                "README",
                "source_code_comment",
                "application_log",
                "csv_cell",
                "api_response",
                "issue_comment",
                "document",
                "terminal_output",
            }.issubset(source_types)
        )
        self.assertTrue(
            {
                "instruction_override",
                "secret_exfiltration",
                "secret_disclosure",
                "tool_misuse",
                "unauthorized_side_effect",
                "policy_override",
                "destructive_command",
            }.issubset(attack_types)
        )


if __name__ == "__main__":
    unittest.main()
