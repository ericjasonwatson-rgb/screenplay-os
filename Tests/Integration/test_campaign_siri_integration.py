"""Source-composition tests; these do NOT substitute for macOS runtime tests."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("campaign_siri", ROOT / "Scripts/validate-campaign-siri-integration.py")
integration = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(integration)


class CampaignSiriCompositionTests(unittest.TestCase):
    def test_reviewed_heads_and_five_file_inventory_are_accepted(self):
        campaign, siri, base = integration.reviewed_inputs(ROOT, "HEAD", integration.SIRI_HEAD)
        self.assertEqual(siri, integration.SIRI_HEAD)
        self.assertEqual(campaign, integration.resolve(ROOT, "HEAD"))
        self.assertEqual(base, "f995ee1d2fe383b1159e0fa9dddd9b76f777696b")

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
