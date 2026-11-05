"""Source-composition tests; these do NOT substitute for macOS runtime tests."""
import contextlib
import hashlib
import importlib.util
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("campaign_siri", ROOT / "Scripts/validate-campaign-siri-integration.py")
integration = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(integration)


class CampaignSiriCompositionTests(unittest.TestCase):
    def test_reviewed_heads_and_source_plus_deletion_inventory_are_accepted(self):
        campaign, siri, base = integration.reviewed_inputs(ROOT, "HEAD", integration.SIRI_HEAD)
        self.assertEqual(siri, integration.SIRI_HEAD)
        self.assertEqual(campaign, integration.resolve(ROOT, "HEAD"))
        self.assertEqual(base, integration.MERGE_BASE)
        self.assertEqual(len(integration.SIRI_INVENTORY), 7)
        self.assertEqual(list(integration.SIRI_INVENTORY.values()).count("D"), 2)

    def test_changed_siri_head_fails_closed(self):
        with self.assertRaisesRegex(integration.IntegrationError, "Siri head changed"):
            integration.reviewed_inputs(ROOT, "HEAD", integration.CAMPAIGN_BASE)

    def test_unrelated_campaign_head_fails_closed(self):
        with self.assertRaisesRegex(integration.IntegrationError, "not a descendant"):
            integration.reviewed_inputs(ROOT, integration.SIRI_HEAD, integration.SIRI_HEAD)

    def test_missing_ref_is_not_fetched_or_guessed(self):
        with self.assertRaises(integration.IntegrationError):
            integration.reviewed_inputs(ROOT, "refs/heads/nonexistent-campaign-integration-fixture", integration.SIRI_HEAD)

    def test_existing_destination_is_never_overwritten(self):
        with tempfile.TemporaryDirectory(prefix="campaign-siri-existing-") as folder:
            path = Path(folder)
            marker = path / "keep.txt"
            marker.write_text("keep")
            with self.assertRaisesRegex(integration.IntegrationError, "already exists"):
                integration.compose(ROOT, path, "HEAD", integration.SIRI_HEAD)
            self.assertEqual(marker.read_text(), "keep")

    def test_composition_preserves_campaign_and_original_siri_tests_without_moving_refs(self):
        refs = integration.git(ROOT, "show-ref").stdout
        source_app = (ROOT / integration.APP).read_bytes()
        campaign = integration.resolve(ROOT, "HEAD")
        with tempfile.TemporaryDirectory(prefix="campaign-siri-test-") as folder:
            destination = Path(folder) / "combined"
            try:
                manifest = integration.compose(ROOT, destination, campaign, integration.SIRI_HEAD)
                self.assertEqual(manifest["campaign_head"], campaign)
                self.assertEqual(manifest["native_tests"], "not run")
                self.assertEqual(manifest["fixture_hygiene"]["status"], "passed")
                self.assertEqual(manifest["fixture_hygiene"]["checker_sha256"],
                                 hashlib.sha256((destination / integration.HYGIENE_PATH).read_bytes()).hexdigest())
                for path, status in integration.SIRI_INVENTORY.items():
                    if status == "D":
                        self.assertFalse((destination / path).exists())
                self.assertEqual(integration.git(destination, "symbolic-ref", "-q", "HEAD", allowed=(1,)).returncode, 1)
                app = (destination / integration.APP).read_text()
                self.assertEqual(app.count(".sheet(isPresented: $model.campaignPresented)"), 1)
                self.assertEqual(app.count("SiriWorkspaceNavigation.consume(model: model)"), 2)
                self.assertNotIn("<<<<<<<", app)
                self.assertEqual((destination / integration.SIRI_TESTS).read_bytes(),
                                 integration.git(ROOT, "show", integration.SIRI_HEAD + ":" + integration.SIRI_TESTS).stdout)
                self.assertEqual((destination / "Tests/ScreenplayEditorTests" / integration.INTEGRATION_TEST).read_bytes(),
                                 (ROOT / integration.TEST_PATH).read_bytes())
                changed = set(integration.git(destination, "diff", "--cached", "--name-only", "-z", campaign).stdout.decode().strip("\0").split("\0"))
                self.assertLessEqual(changed, integration.SIRI_FILES | {"Tests/ScreenplayEditorTests/" + integration.INTEGRATION_TEST})
                # The source/head is not changed by materializing the conflict
                # resolution in an isolated detached worktree.
                self.assertEqual(integration.git(ROOT, "show-ref").stdout, refs)
                self.assertEqual((ROOT / integration.APP).read_bytes(), source_app)
            finally:
                if destination.exists():
                    integration.git(ROOT, "worktree", "remove", "--force", str(destination))

    def test_fixture_deletions_cannot_be_reclassified_as_additions(self):
        removed = next(path for path, status in integration.SIRI_INVENTORY.items() if status == "D")
        with mock.patch.dict(integration.SIRI_INVENTORY, {removed: "A"}):
            with self.assertRaisesRegex(integration.IntegrationError, "change inventory"):
                integration.reviewed_inputs(ROOT, "HEAD", integration.SIRI_HEAD)

    def test_changed_merge_base_fails_closed(self):
        with mock.patch.object(integration, "MERGE_BASE", "0" * 40):
            with self.assertRaisesRegex(integration.IntegrationError, "merge base changed"):
                integration.reviewed_inputs(ROOT, "HEAD", integration.SIRI_HEAD)

    def test_campaign_before_sanitized_baseline_is_rejected(self):
        with self.assertRaisesRegex(integration.IntegrationError, "not a descendant"):
            integration.reviewed_inputs(ROOT, "be5a75ac487c44f79e038ae2e0dda7f60d3d1c62", integration.SIRI_HEAD)

    def test_missing_hygiene_checker_fails_closed(self):
        with tempfile.TemporaryDirectory(prefix="campaign-hygiene-missing-") as folder:
            with self.assertRaisesRegex(integration.IntegrationError, "missing the regular fixture-hygiene checker"):
                integration.check_fixture_hygiene(Path(folder))

    def test_failed_hygiene_checker_is_not_a_pass(self):
        with tempfile.TemporaryDirectory(prefix="campaign-hygiene-fail-") as folder:
            root = Path(folder)
            checker = root / integration.HYGIENE_PATH
            checker.parent.mkdir()
            checker.write_text("import sys\nsys.stderr.write('Synthetic rejection fixture')\nsys.exit(9)\n")
            with self.assertRaisesRegex(integration.IntegrationError, "hygiene failed .*exit 9"):
                integration.check_fixture_hygiene(root)

    def test_prepare_only_hygiene_failure_returns_failure_and_removes_worktree(self):
        refs = integration.git(ROOT, "show-ref").stdout
        with tempfile.TemporaryDirectory(prefix="campaign-hygiene-gate-") as folder:
            destination = Path(folder) / "combined"
            with mock.patch.object(integration, "check_fixture_hygiene",
                                   side_effect=integration.IntegrationError("Synthetic hygiene rejection")) as hygiene:
                with contextlib.redirect_stderr(io.StringIO()) as output:
                    result = integration.main(["--prepare-only", "--worktree", str(destination)])
            self.assertEqual(result, 1)
            self.assertIn("Synthetic hygiene rejection", output.getvalue())
            hygiene.assert_called_once_with(destination)
            self.assertFalse(destination.exists())
            self.assertEqual(integration.git(ROOT, "show-ref").stdout, refs)

    def test_patch_clears_a_request_before_applying_the_modal_guard(self):
        patch = (ROOT / integration.PATCH_PATH).read_text()
        self.assertIn("NSApp?.modalWindow != nil", patch)
        self.assertIn("$0.attachedSheet != nil", patch)
        self.assertIn("preferences.removeObject(forKey: pendingKey)\n+        guard !navigationIsBlocked", patch)
        self.assertIn('Requested the ScreenplayOS', patch)
        self.assertNotIn('+        return .result(dialog: "Opening', patch)
        self.assertNotIn("onDismiss", patch)

    def test_cli_rejects_worktree_inside_source_checkout(self):
        result = subprocess.run(["python3", str(ROOT / "Scripts/validate-campaign-siri-integration.py"),
                                 "--prepare-only", "--worktree", str(ROOT / ".build/not-a-worktree")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("outside the source checkout", result.stderr)


if __name__ == "__main__":
    unittest.main()
