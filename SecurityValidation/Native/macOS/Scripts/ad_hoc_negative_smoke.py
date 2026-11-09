#!/usr/bin/env python3
"""macOS-only negative test: ad-hoc helper must refuse to start.

No service listener is launched, no provider connection and no real IP.
This does NOT test valid, production Developer ID signing.
"""
import pathlib
import plistlib
import shutil
import subprocess
import sys
import tempfile

if len(sys.argv) != 2:
    raise SystemExit("usage: ad_hoc_negative_smoke.py <swift-bin-directory>")

binary = pathlib.Path(sys.argv[1]) / "ShieldMacService"
assert binary.is_file(), f"missing executable: {binary}"

with tempfile.TemporaryDirectory(prefix="cips-untrusted-") as root:
    app = pathlib.Path(root) / "ShieldMacService.app"
    macos = app / "Contents" / "MacOS"
    macos.mkdir(parents=True)
    shutil.copy2(binary, macos / "ShieldMacService")
    info = {
        "CFBundleIdentifier": "com.example.shield.helper",
        "CFBundleExecutable": "ShieldMacService",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "1",
        "CFBundleShortVersionString": "0.0.0-test",
        "CIPSTeamID": "AB12345678",
        "CIPSAgentBundleID": "com.example.shield.agent",
        "CIPSReviewerBundleID": "com.example.shield.reviewer",
        "CIPSAgentMachService": "com.example.shield.agentService",
        "CIPSReviewerMachService": "com.example.shield.reviewerService",
    }
    with (app / "Contents" / "Info.plist").open("wb") as f:
        plistlib.dump(info, f)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True, capture_output=True, timeout=30)
    proc = subprocess.run([str(macos / "ShieldMacService")], capture_output=True, timeout=8)
    print(f"untrusted helper exit code={proc.returncode}")
    print("helper stderr:", proc.stderr.decode("utf-8", "replace").strip())
    assert proc.returncode == 78, "ad-hoc helper failed to reject its identity"
    assert b"helper code-signing identity is not trusted" in proc.stderr, (
        "rejection did not reach helper self-signing validation"
    )
print("PASS: unsigned-Team-ID helper refused before accepting connections")
