"""Portable contract tests. These do not claim a macOS build/sign/launch pass."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("campaign_app_validation", ROOT / "Scripts/validate-campaign-app.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)
HEAD = "1234567890abcdef1234567890abcdef12345678"


class AppPackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.app = self.root / "ScreenplayOS.app"
        for source in MODULE.RESOURCE_SOURCES.values():
            path = self.repo / source
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(("fixture: " + source).encode())
        (self.repo / MODULE.RESOURCE_SOURCES["pricing.json"]).write_text(json.dumps({
            "currency": "USD", "proMonthlyCents": 1200, "proAnnualCents": 9900,
            "foundingAnnualCents": 6900, "studioMinimumSeats": 3,
            "studioMonthlyPerSeatCents": None, "studioAnnualPerSeatCents": None,
            "perpetualEligibilityPaidMonths": 12}))
        self.package_fixture()

    def package_fixture(self):
        # Exercise package-app.sh's actual Python payload, not a parallel copy of
        # its plist/resource/manifest construction. Shell/Swift/signing stay native.
        source = (ROOT / "Scripts/package-app.sh").read_text()
        script = source.split("<<'PY'\n", 1)[1].split("\nPY\n", 1)[0]
        executable = self.root / "ScreenplayOS"
        executable.write_bytes(b"mock executable, not Mach-O")
        executable.chmod(0o755)
        previous = Path.cwd()
        os.chdir(self.repo)
        try:
            with mock.patch.object(sys, "argv", ["-", str(executable), str(self.app), "release"]), \
                 mock.patch.dict(os.environ, {"SCREENPLAYOS_SOURCE_DIRTY": "0", "SCREENPLAYOS_APP_VERSION": "0.1", "SCREENPLAYOS_BUILD_NUMBER": "1"}), \
                 mock.patch("subprocess.check_output", side_effect=[HEAD + "\n", HEAD[:7] + "\n"]), \
                 contextlib.redirect_stdout(io.StringIO()):
                exec(compile(script, "package-app.sh:Python", "exec"), {"__name__": "__main__"})
        finally:
            os.chdir(previous)

    def verify(self):
        return MODULE.verify_bundle(self.app, self.repo, HEAD)

    def edit_plist(self, key, value):
        path = self.app / "Contents/Info.plist"
        info = plistlib.loads(path.read_bytes())
        info[key] = value
        path.write_bytes(plistlib.dumps(info))

    def test_actual_package_payload_meets_metadata_and_resource_contract(self):
        result = self.verify()
        self.assertEqual(result["status"], "passed")
        self.assertEqual(len(result["resourceSHA256"]), 11)
        self.assertEqual(len(result["bundleTreeSHA256"]), 64)
        self.assertEqual(result["pricing"]["proMonthlyCents"], 1200)
        manifest = json.loads((self.app / "Contents/Resources/BuildManifest.json").read_text())
        self.assertEqual(manifest["sourceRevision"], HEAD)
        self.assertIs(manifest["sourceDirty"], False)

    def test_incorrect_or_missing_plist_fields_fail(self):
        for key, bad in (("ScreenplayOSSourceRevision", HEAD[:7]),
                         ("ScreenplayOSSourceDirty", True),
                         ("ScreenplayOSBuildConfiguration", "debug"),
                         ("CFBundleExecutable", "Other"),
                         ("CFBundleIdentifier", "another.app"),
                         ("CFBundleVersion", "2"),
                         ("CFBundleShortVersionString", "0.2"),
                         ("ScreenplayOSRevision", HEAD[:7] + "-dirty"),
                         ("LSMinimumSystemVersion", "14.0"),
                         ("NSHighResolutionCapable", 1),
                         ("CFBundleDocumentTypes", [])):
            with self.subTest(field=key):
                path = self.app / "Contents/Info.plist"
                original = path.read_bytes()
                self.edit_plist(key, bad)
                with self.assertRaises(MODULE.ValidationError):
                    self.verify()
                path.write_bytes(original)

    def test_missing_and_altered_each_resource_fail(self):
        for name in MODULE.RESOURCE_SOURCES:
            with self.subTest(resource=name):
                path = self.app / "Contents/Resources" / name
                original = path.read_bytes()
                path.unlink()
                with self.assertRaisesRegex(MODULE.ValidationError, "Missing or unsafe"):
                    self.verify()
                path.write_bytes(original + b"altered")
                with self.assertRaisesRegex(MODULE.ValidationError, "differs from source"):
                    self.verify()
                path.write_bytes(original)

    def test_matching_tampered_manifest_does_not_mask_source_mismatch(self):
        path = self.app / "Contents/Resources/pricing.json"
        path.write_text('{"currency": "EUR"}')
        manifest_path = self.app / "Contents/Resources/BuildManifest.json"
        manifest = json.loads(manifest_path.read_text())
        manifest["resources"]["pricing.json"]["sha256"] = MODULE.sha256(path)
        manifest_path.write_text(json.dumps(manifest))
        with self.assertRaisesRegex(MODULE.ValidationError, "differs from source"):
            self.verify()

    def test_incorrect_manifest_source_revision_hash_and_inventory_fail(self):
        path = self.app / "Contents/Resources/BuildManifest.json"
        original = path.read_bytes()
        for mutate in (
            lambda value: value.update(sourceRevision="0" * 40),
            lambda value: value.update(sourceDirty=True),
            lambda value: value.update(buildConfiguration="debug"),
            lambda value: value.update(schemaVersion=True),
            lambda value: value["resources"]["pricing.json"].update(sha256="0" * 64),
            lambda value: value["resources"].pop("pricing.json"),
        ):
            manifest = json.loads(original)
            mutate(manifest)
            path.write_text(json.dumps(manifest))
            with self.assertRaises(MODULE.ValidationError):
                self.verify()
        path.write_bytes(original)

    def test_unexpected_resources_fail(self):
        (self.app / "Contents/Resources/private.txt").write_text("extra")
        with self.assertRaisesRegex(MODULE.ValidationError, "unexpected"):
            self.verify()

    def test_symlinked_resource_rejected_even_when_content_matches(self):
        path = self.app / "Contents/Resources/pricing.json"
        path.unlink()
        path.symlink_to(self.repo / MODULE.RESOURCE_SOURCES["pricing.json"])
        with self.assertRaisesRegex(MODULE.ValidationError, "unsafe"):
            self.verify()

    def test_nonexecutable_binary_fails(self):
        (self.app / "Contents/MacOS/ScreenplayOS").chmod(0o644)
        with self.assertRaisesRegex(MODULE.ValidationError, "not executable"):
            self.verify()

    def test_negative_controls_reject_actual_copy_mutations(self):
        result = MODULE.negative_resource_checks(self.app, self.repo, HEAD, self.root)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(set(result["cases"].values()), {"rejected"})
        self.assertFalse((self.root / "Tampered.app").exists())
        self.verify()

    def test_output_existing_directory_or_file_not_overwritten(self):
        for path in (self.repo, self.root / "existing.json"):
            if path != self.repo:
                path.write_text("keep")
            with self.assertRaisesRegex(MODULE.ValidationError, "already exists"):
                MODULE.prepare_output(path, self.repo)
        self.assertEqual((self.root / "existing.json").read_text(), "keep")

    def test_output_in_checkout_and_symlink_into_checkout_rejected(self):
        with self.assertRaisesRegex(MODULE.ValidationError, "outside"):
            MODULE.prepare_output(self.repo / "evidence", self.repo)
        alias = self.root / "alias"
        alias.symlink_to(self.repo, target_is_directory=True)
        with self.assertRaisesRegex(MODULE.ValidationError, "outside"):
            MODULE.prepare_output(alias / "evidence", self.repo)
        dangling = self.root / "dangling"
        dangling.symlink_to(self.root / "missing")
        with self.assertRaisesRegex(MODULE.ValidationError, "already exists"):
            MODULE.prepare_output(dangling, self.repo)

    def test_output_new_external_folder_accepted(self):
        output = MODULE.prepare_output(self.root / "evidence", self.repo)
        self.assertTrue(output.is_dir())
        self.assertFalse(list(output.iterdir()))

    def test_launch_needs_both_hosted_runner_flags(self):
        for env in ({}, {"GITHUB_ACTIONS": "true"}, {"RUNNER_ENVIRONMENT": "github-hosted"},
                    {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "self-hosted"}):
            with self.assertRaisesRegex(MODULE.ValidationError, "disposable"):
                MODULE.check_launch_permission(True, env)
        MODULE.check_launch_permission(False, {})
        MODULE.check_launch_permission(True, {"GITHUB_ACTIONS": "true", "RUNNER_ENVIRONMENT": "github-hosted"})

    def test_generated_accessor_must_use_owned_build_fallback(self):
        scratch = self.root / "build"
        accessor = scratch / "arm64-apple-macosx/release/ScreenplayDomain.build/DerivedSources/resource_bundle_accessor.swift"
        accessor.parent.mkdir(parents=True)
        accessor.write_text(f'let mainPath = Bundle.main.bundleURL\nlet buildPath = "{scratch}/resource.bundle"\n')
        self.assertEqual(MODULE.find_accessor(scratch), accessor)
        accessor.write_text('let mainPath = Bundle.main.bundleURL\nlet buildPath = "/another/build/resource.bundle"\n')
        with self.assertRaisesRegex(MODULE.ValidationError, "owned scratch"):
            MODULE.find_accessor(scratch)

    def test_hidden_scratch_restored_on_success_and_exception(self):
        scratch = self.root / "build"
        scratch.mkdir()
        (scratch / "sentinel").write_text("keep")
        for fail in (False, True):
            try:
                with MODULE.hidden_scratch(scratch):
                    self.assertFalse(scratch.exists())
                    if fail:
                        raise RuntimeError("probe failed")
            except RuntimeError:
                pass
            self.assertEqual((scratch / "sentinel").read_text(), "keep")
            self.assertFalse(scratch.with_name("build.hidden").exists())

    def test_scratch_hiding_rejects_conflict_without_changes(self):
        scratch = self.root / "build"
        scratch.mkdir()
        scratch.with_name("build.hidden").mkdir()
        with self.assertRaises(MODULE.ValidationError):
            with MODULE.hidden_scratch(scratch):
                self.fail("must not enter")
        self.assertTrue(scratch.is_dir())

    def test_native_checks_require_requested_architecture_and_adhoc_signature(self):
        runner = mock.Mock()
        runner.run.side_effect = ["arm64", "OK", "valid", "Signature=adhoc\nTeamIdentifier=not set"]
        self.assertEqual(MODULE.verify_native(self.app, "arm64", runner)["status"], "passed")
        runner.run.side_effect = ["x86_64"]
        with self.assertRaisesRegex(MODULE.ValidationError, "architecture"):
            MODULE.verify_native(self.app, "arm64", runner)
        runner.run.side_effect = ["arm64", "OK", "valid", "Authority=Developer ID\nTeamIdentifier=ABC"]
        with self.assertRaisesRegex(MODULE.ValidationError, "ad-hoc"):
            MODULE.verify_native(self.app, "arm64", runner)

    def test_probe_compares_all_pricing_fields(self):
        pricing = self.verify()["pricing"]
        runner = mock.Mock()
        normalized = {key: value for key, value in pricing.items() if value is not None}
        runner.run.return_value = json.dumps(normalized)
        result = MODULE.run_probe(self.root / "probe", self.root / "expected", pricing, runner, cwd=self.root)
        self.assertTrue(result["entireDecodedConfigurationCompared"])
        normalized["foundingAnnualCents"] += 1
        runner.run.return_value = json.dumps(normalized)
        with self.assertRaisesRegex(MODULE.ValidationError, "full source"):
            MODULE.run_probe(self.root / "probe", self.root / "expected", pricing, runner, cwd=self.root)

    def test_dirty_checkout_rejected(self):
        runner = mock.Mock()
        runner.run.side_effect = [HEAD, " M source.swift"]
        with self.assertRaisesRegex(MODULE.ValidationError, "dirty"):
            MODULE.git_state(self.repo, runner)

    def test_failed_run_writes_evidence_but_no_artifacts(self):
        output = self.root / "failure-evidence"
        with mock.patch.object(MODULE, "REPO", self.repo), \
             mock.patch.object(MODULE, "validate", side_effect=MODULE.ValidationError("native gate unavailable")), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            result = MODULE.main(["--output", str(output)])
        self.assertEqual(result, 1)
        self.assertEqual([path.name for path in output.iterdir()], ["evidence.json"])
        evidence = json.loads((output / "evidence.json").read_text())
        self.assertEqual(evidence["status"], "failed")
        self.assertIn("native gate unavailable", evidence["error"])

    def test_launch_failure_stops_only_spawned_child(self):
        process = mock.Mock(pid=1234)
        process.poll.side_effect = [0, 0, 0]
        with mock.patch.object(MODULE.subprocess, "Popen", return_value=process), \
             mock.patch.object(MODULE, "stop_child") as cleanup:
            with self.assertRaisesRegex(MODULE.ValidationError, "exited"):
                MODULE.launch_smoke(self.app, self.root / "window-probe", mock.Mock())
        cleanup.assert_called_once_with(process)

    def test_runtime_negatives_require_specific_fatal_errors_after_resigning(self):
        probe = self.root / "ResourceProbe.app/Contents/MacOS/ResourceProbe"
        probe.parent.mkdir(parents=True)
        (probe.parents[1] / "Resources").mkdir()
        (probe.parents[1] / "Resources/pricing.json").write_text("{}")
        probe.write_bytes(b"fake probe")
        runner = mock.Mock(last_returncode=-4)
        runner.run.side_effect = ["", "", "Fatal error: missing bundle at path", "", "",
                                  "Fatal error: The bundled pricing configuration is missing or invalid."]
        result = MODULE.negative_runtime_checks(probe, self.root / "expected", self.root, "missing bundle", runner)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(runner.run.call_count, 6)
        self.assertTrue(all(value["signatureReverified"] for value in result["cases"].values()))
        self.assertEqual(runner.run.call_args_list[0].args[0][:4], ["codesign", "--force", "--sign", "-"])
        self.assertEqual(runner.run.call_args_list[1].args[0][:4], ["codesign", "--verify", "--deep", "--strict"])

    def test_runtime_negative_arbitrary_nonzero_is_not_a_pass(self):
        probe = self.root / "ResourceProbe.app/Contents/MacOS/ResourceProbe"
        probe.parent.mkdir(parents=True)
        (probe.parents[1] / "Resources").mkdir()
        (probe.parents[1] / "Resources/pricing.json").write_text("{}")
        probe.write_bytes(b"fake probe")
        runner = mock.Mock(last_returncode=-9)
        runner.run.side_effect = ["", "", "OS signature rejected"]
        with self.assertRaisesRegex(MODULE.ValidationError, "unexpected reason"):
            MODULE.negative_runtime_checks(probe, self.root / "expected", self.root, "missing bundle", runner)

    def test_command_timeout_terminates_owned_process_group_and_records_failure(self):
        process = mock.Mock(pid=4321, returncode=-15)
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired("build", 1), -15, -15]
        evidence = {}
        with mock.patch.object(MODULE.subprocess, "Popen", return_value=process) as popen, \
             mock.patch.object(MODULE.os, "killpg") as killpg, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(MODULE.ValidationError, "timed out"):
                MODULE.Runner(evidence).run(["fake-build"], timeout=1)
        self.assertTrue(popen.call_args.kwargs["start_new_session"])
        self.assertEqual(killpg.call_args_list, [mock.call(4321, signal.SIGTERM), mock.call(4321, signal.SIGKILL)])
        self.assertTrue(evidence["commands"][0]["timedOut"])

    def test_command_cleanup_handles_exited_leader_with_descendants(self):
        process = mock.Mock(pid=4321, returncode=0)
        process.poll.return_value = 0
        with mock.patch.object(MODULE.os, "killpg") as killpg:
            MODULE.stop_command_tree(process)
        self.assertEqual(killpg.call_args_list, [mock.call(4321, signal.SIGTERM), mock.call(4321, signal.SIGKILL)])
        self.assertEqual(process.wait.call_count, 2)

    def test_command_interrupt_cleans_owned_group_then_propagates(self):
        process = mock.Mock(pid=4321, returncode=-15)
        process.poll.return_value = None
        process.wait.side_effect = [KeyboardInterrupt(), -15, -15]
        evidence = {}
        with mock.patch.object(MODULE.subprocess, "Popen", return_value=process), \
             mock.patch.object(MODULE.os, "killpg") as killpg, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(KeyboardInterrupt):
                MODULE.Runner(evidence).run(["fake-build"])
        self.assertEqual(killpg.call_args_list, [mock.call(4321, signal.SIGTERM), mock.call(4321, signal.SIGKILL)])
        self.assertTrue(evidence["commands"][0]["interrupted"])

    def test_launch_requires_finished_matching_main_window(self):
        process = mock.Mock(pid=1234)
        process.poll.side_effect = [None, None, None, None, 0]
        runner = mock.Mock()
        runner.run.side_effect = [
            json.dumps({"pid": 1234, "visibleWindowCount": 1, "finishedLaunching": False, "executableMatches": True}),
            json.dumps({"pid": 1234, "visibleWindowCount": 1, "finishedLaunching": True, "executableMatches": True}),
        ]
        with mock.patch.object(MODULE.subprocess, "Popen", return_value=process), \
             mock.patch.object(MODULE, "stop_child") as cleanup, mock.patch.object(MODULE.time, "sleep"):
            result = MODULE.launch_smoke(self.app, self.root / "window-probe", runner)
        self.assertEqual(result["status"], "passed")
        self.assertEqual(result["minimumWindowSize"], {"width": 900, "height": 560})
        self.assertEqual(runner.run.call_count, 2)
        cleanup.assert_called_once_with(process)

    def test_stop_child_escalates_only_owned_process_after_timeout(self):
        process = mock.Mock()
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired("app", 5), 0]
        MODULE.stop_child(process)
        process.terminate.assert_called_once_with()
        process.kill.assert_called_once_with()
        self.assertEqual(process.wait.call_count, 2)


if __name__ == "__main__":
    unittest.main()
