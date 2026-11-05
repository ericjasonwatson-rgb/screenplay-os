#!/usr/bin/env python3
"""Small deterministic tests for the current-tree fixture guard."""
import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("fixture_hygiene", Path(__file__).with_name("check-fixture-hygiene.py"))
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)


class FixtureHygieneTests(unittest.TestCase):
    def test_original_filename_and_case_variants_are_blocked(self):
        for name in ["Tests/Fixtures/Defenders_of_Cat_Island.fdx", "Tests/Fixtures/CAT-ISLAND.json"]:
            self.assertIsNotNone(guard.violation(name, b"{}"))

    def test_renamed_text_is_still_blocked_without_printing_it(self):
        for text in ["Cat Island", "STARGAZER", "Mewseum", "The Savannah Rubies"]:
            self.assertIsNotNone(guard.violation("Tests/Fixtures/renamed.json", text.encode()))

    def test_independent_synthetic_and_generic_effect_text_are_allowed(self):
        self.assertIsNone(guard.violation("Tests/Fixtures/Synthetic.json", b'The Paper Bridge. A beam of light.'))

    def test_binary_pixels_are_not_claimed_scanned(self):
        self.assertIsNone(guard.violation("Tests/Fixtures/Synthetic.png", b"\x89PNG\x00\xff"))

    def test_invalid_encoded_source_requires_review(self):
        self.assertIsNotNone(guard.violation("Tests/Fixtures/Synthetic.json", b"\xff"))


if __name__ == "__main__":
    unittest.main()
