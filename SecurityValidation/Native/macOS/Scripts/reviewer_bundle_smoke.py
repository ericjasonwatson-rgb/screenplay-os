#!/usr/bin/env python3
"""macOS CI: inspect signed-peer requirements and fail-closed reviewer apps."""
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile

if len(sys.argv) != 2:
    raise SystemExit("usage: reviewer_bundle_smoke.py <swift-build-bin-directory>")

build_dir = pathlib.Path(sys.argv[1])
tool = pathlib.Path(__file__).with_name("package_reviewer_app.py")
team = "AB12345678"
reviewer = "com.creativeipshield.reviewer.validation"
agent = "com.creativeipshield.agent.validation"
helper = "com.creativeipshield.helper.validation"
agent_mach = "com.creativeipshield.agentservice.validation"
reviewer_mach = "com.creativeipshield.reviewservice.validation"


def call(*args, timeout=30):
    return subprocess.run(list(map(str, args)), text=True,
                          capture_output=True, timeout=timeout)


def assert_denied(result, reason):
    if result.returncode == 0:
        raise AssertionError("Unexpectedly accepted: " + reason)


with tempfile.TemporaryDirectory(prefix="cips-reviewer-signing-",
                                 dir=str(pathlib.Path.home().resolve())) as directory:
    root = pathlib.Path(directory)
    os.chmod(root, 0o700)
    demo = root / "DemoReviewer.app"
    candidate = root / "CandidateReviewer.app"
    common = ("--bundle-id", reviewer)
    valid_candidate_config = (
        *common, "--team-id", team,
        "--agent-bundle-id", agent,
        "--helper-bundle-id", helper,
        "--agent-mach-service", agent_mach,
        "--reviewer-mach-service", reviewer_mach
    )
    demo_build = call(sys.executable, tool, "assemble",
                      "--binary", build_dir / "ShieldReviewerDemoApp",
                      "--app", demo, *common)
    assert demo_build.returncode == 0, demo_build.stderr
    assert demo_build.stdout.strip() == "ASSEMBLED_UNSIGNED_SYNTHETIC_REVIEWER_APP"

    candidate_build = call(
        sys.executable, tool, "assemble-candidate",
        "--binary", build_dir / "ShieldReviewerCandidateApp",
        "--app", candidate, *valid_candidate_config
    )
    assert candidate_build.returncode == 0, candidate_build.stderr
    assert candidate_build.stdout.strip() == "ASSEMBLED_UNSIGNED_FAIL_CLOSED_REVIEWER_CANDIDATE"

    with (candidate / "Contents" / "Info.plist").open("rb") as stream:
        data = plistlib.load(stream)
    assert data["CFBundleIdentifier"] == reviewer
    assert data["CIPSReviewerBundleID"] == reviewer
    assert data["CIPSTeamID"] == team
    assert data["CIPSReviewerCandidate"] is True
    assert data["CIPSValidationOnly"] is True
    assert data["CIPSNoRealApprovalOrEgress"] is True
    assert data["CFBundleExecutable"] == "ShieldReviewerCandidateApp"
    for app in (demo, candidate):
        check = call("plutil", "-lint", app / "Contents" / "Info.plist")
        assert check.returncode == 0, check.stderr

    assert_denied(call(sys.executable, tool, "assemble",
                       "--binary", build_dir / "ShieldReviewerDemoApp",
                       "--app", demo, *common),
                  "overwriting synthetic demo")
    assert_denied(call(sys.executable, tool, "assemble-candidate",
                       "--binary", build_dir / "ShieldReviewerCandidateApp",
                       "--app", candidate, *valid_candidate_config),
                  "overwriting candidate")
    assert_denied(call(sys.executable, tool, "assemble-candidate",
                       "--binary", build_dir / "ShieldReviewerCandidateApp",
                       "--app", root / "Invalid.app", *common,
                       "--team-id", team,
                       "--agent-bundle-id", reviewer,
                       "--helper-bundle-id", helper,
                       "--agent-mach-service", agent_mach,
                       "--reviewer-mach-service", reviewer_mach),
                  "agent impersonating reviewer bundle")

    # Mac's code signing requirement parser must accept the strict Developer
    # ID Application OID expression, not merely reject an invalid expression.
    from package_reviewer_app import developer_id_requirement
    expression = developer_id_requirement(reviewer, team)
    assert "certificate 1[field.1.2.840.113635.100.6.2.6] exists" in expression
    assert "certificate leaf[field.1.2.840.113635.100.6.1.13] exists" in expression
    assert 'certificate leaf[subject.OU] = "' + team + '"' in expression
    compiled = call("csreq", "-r", expression, "-b", root / "developer-id-requirement.bin")
    assert compiled.returncode == 0, compiled.stderr

    for app in (demo, candidate):
        verify = (sys.executable, tool, "verify-release",
                  "--app", app, *common, "--team-id", team)
        assert_denied(call(*verify), "unsigned reviewer bundle")
        assert_denied(call(sys.executable, tool, "sign-release",
                           "--app", app, *common, "--team-id", team,
                           "--identity", "-"), "ad-hoc release identity")
        signed = call("codesign", "--force", "--sign", "-",
                      "--timestamp=none", app)
        assert signed.returncode == 0, signed.stderr
        assert call("codesign", "--verify", "--strict", app).returncode == 0
        # POSITIVE CONTROL: a signed test bundle should satisfy a literal
        # identifier-only expression. Without the leading '=' codesign would
        # interpret the string as a filesystem path, making every test fail
        # regardless of the actual certificate requirements.
        allowed_identifier = call(
            "codesign", "--verify", "--strict", "-R",
            '=identifier "' + reviewer + '"', app)
        assert allowed_identifier.returncode == 0, allowed_identifier.stderr
        # NEGATIVE CONTROLS: wrong identity and missing Developer ID
        # certificate extensions must each fail when evaluated as expressions.
        assert_denied(call(
            "codesign", "--verify", "--strict", "-R",
            '=identifier "' + reviewer + '.wrong"', app),
            "literal requirement with incorrect bundle identifier")
        assert_denied(call(
            "codesign", "--verify", "--strict", "-R",
            "=" + expression, app),
            "Developer ID Application-only literal requirement")
        assert_denied(call(*verify), "ad-hoc signed reviewer bundle")

    # The candidate's actual executable must fail at signing preflight before
    # displaying a UI, opening Keychain or prompting for authentication.
    candidate_bin = candidate / "Contents" / "MacOS" / "ShieldReviewerCandidateApp"
    launched = call(candidate_bin, timeout=8)
    assert launched.returncode == 78, (
        f"ad-hoc candidate exit={launched.returncode} "
        f"stdout={launched.stdout!r} stderr={launched.stderr!r}"
    )
    assert "not trusted" in launched.stderr or "missing signed" in launched.stderr

print("PASS: Developer ID literal expression positive/negative controls; .app "
      "assembled; unsigned/ad-hoc release and candidate startup rejected")
