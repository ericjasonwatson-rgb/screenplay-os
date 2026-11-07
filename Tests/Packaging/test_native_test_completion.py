import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("native_completion", ROOT / "Scripts/check-native-test-completion.py")
completion = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(completion)


class NativeCompletionTests(unittest.TestCase):
    def test_full_result_accepts_native_summary_after_xctest(self):
        self.assertEqual(completion.verify("Executed 0 tests, with 0 failures\n"
            "◇ Test run started.\n✔ Test run with 597 tests passed after 206.773 seconds.\n"), 597)

    def test_color_and_one_test_are_supported(self):
        self.assertEqual(completion.verify("\x1b[32m✔ Test run with 1 test passed after 0.001 seconds.\x1b[0m\n"), 1)

    def test_truncated_zero_empty_failed_or_duplicate_output_never_passes(self):
        good = "✔ Test run with 597 tests passed after 206.773 seconds.\n"
        for output in ("", "Executed 0 tests, with 0 failures\n",
                       "◇ Test nativePicker() started.\n", "✔ Suite native passed after 1.0 seconds.\n",
                       "✔ Test run with 0 tests passed after 0.0 seconds.\n", good + good,
                       "✘ Test fixture() failed\n" + good, "Test fixture() recorded an issue\n" + good,
                       "✘ Test run with 597 tests failed after 206.773 seconds with 1 issue.\n"):
            with self.subTest(output=output), self.assertRaises(ValueError):
                completion.verify(output)

    def test_cli_reports_failure_and_success_without_echoing_test_contents(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "test-output.txt"
            output.write_text("Private fixture text\n◇ Test picker() started.\n")
            with contextlib.redirect_stderr(io.StringIO()) as error:
                self.assertEqual(completion.main([str(output)]), 1)
            self.assertNotIn("Private fixture", error.getvalue())
            output.write_text("✔ Test run with 597 tests passed after 1.0 seconds.\n")
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(completion.main([str(output)]), 0)


if __name__ == "__main__":
    unittest.main()
