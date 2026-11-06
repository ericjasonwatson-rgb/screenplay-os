#!/usr/bin/env python3
"""macOS CI: verify synthetic app packaging and signing fail-closed rules."""
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile

if len(sys.argv) != 2:
    raise SystemExit("usage: reviewer_bundle_smoke.py <swift-build-bin-directory>")
binary = pathlib.Path(sys.argv[1]) / "ShieldReviewerDemoApp"
tool = pathlib.Path(__file__).with_name("package_reviewer_app.py")
bundle_id = "com.creativeipshield.reviewer.validation"
team = "AB12345678"


def call(*args):
    return subprocess.run([str(x) for x in args],
                          capture_output=True, text=True, timeout=30)


def denied(result, reason):
    assert result.returncode != 0, "Unexpectedly accepted " + reason


with tempfile.TemporaryDirectory(prefix="cips-reviewer-ci-",
                                 dir=str(pathlib.Path.home().resolve())) as temp:
    app = pathlib.Path(temp) / "Reviewer.app"
    common = ("--app", app, "--bundle-id", bundle_id)
    first = call(sys.executable, tool, "assemble", "--binary", binary, *common)
    assert first.returncode == 0, first.stderr
    assert first.stdout.strip() == "ASSEMBLED_UNSIGNED_SYNTHETIC_REVIEWER_APP"
    with (app / "Contents" / "Info.plist").open("rb") as stream:
        metadata = plistlib.load(stream)
    assert metadata["CFBundleIdentifier"] == bundle_id
    assert metadata["CIPSValidationOnly"] is True
    assert metadata["CIPSNoRealApprovalOrEgress"] is True
    assert metadata["CFBundleExecutable"] == "ShieldReviewerDemoApp"
    assert call("plutil", "-lint", app / "Contents" / "Info.plist").returncode == 0
    denied(call(sys.executable, tool, "assemble", "--binary", binary, *common),
           "overwrite of an existing bundle")
    verification = (sys.executable, tool, "verify-release",
                    *common, "--team-id", team)
    denied(call(*verification), "unsigned bundle")
    denied(call(sys.executable, tool, "sign-release", *common,
                "--team-id", team, "--identity", "-"),
           "ad-hoc release signing identity")
    # CI intentionally gives the SYNTHETIC bundle an ad-hoc signature;
    # this is not a valid Developer ID Application signature.
    signed = call("codesign", "--force", "--sign", "-", "--timestamp=none", app)
    assert signed.returncode == 0, signed.stderr
    assert call("codesign", "--verify", "--strict", app).returncode == 0
    denied(call(*verification), "ad-hoc signed bundle")

print("PASS: reviewer .app assembled; unsigned and ad-hoc release identities denied")
