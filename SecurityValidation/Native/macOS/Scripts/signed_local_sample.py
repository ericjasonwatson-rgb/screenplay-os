#!/usr/bin/env python3
"""Sign and exercise the isolated local reviewer/helper sample on the owner's Mac."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import uuid

from package_reviewer_app import assemble, developer_id_requirement, reviewer_config, sign_release


def run(args):
    subprocess.run(args, check=True)


def exercise(args):
    prefix = f"com.creativeipshield.sample.{uuid.uuid4().hex[:12]}"
    reviewer_id = prefix + ".reviewer"
    helper_id = prefix + ".helper"
    service = prefix + ".xpc"
    config = reviewer_config(
        args.team_id, reviewer_id, prefix + ".agent", helper_id, prefix + ".unused", service
    )
    config["CIPSSignedSample"] = True
    sample_arg = "--signed-local-sample"

    with tempfile.TemporaryDirectory(prefix="cips-signed-sample-") as root:
        root = Path(root).resolve()
        reviewer = root / "SampleReviewer.app"
        assemble(args.build_dir / "ShieldReviewerCandidateApp", reviewer,
                 reviewer_id, "candidate", config)
        helper = root / "SampleHelper.app"
        helper_binary = helper / "Contents" / "MacOS" / "ShieldMacService"
        helper_binary.parent.mkdir(parents=True)
        shutil.copy2(args.build_dir / "ShieldMacService", helper_binary)
        helper_info = {key: value for key, value in config.items() if key != "CIPSReviewerCandidate"}
        helper_info.update(
            CFBundleIdentifier=helper_id, CFBundleExecutable=helper_binary.name,
            CFBundlePackageType="APPL", CFBundleVersion="1",
            CIPSValidationOnly=True, CIPSNoRealApprovalOrEgress=True,
        )
        (helper / "Contents" / "Info.plist").write_bytes(plistlib.dumps(helper_info))

        sign_release(reviewer, reviewer_id, args.team_id, args.identity)
        run(["codesign", "--force", "--options", "runtime", "--timestamp",
             "--sign", args.identity, str(helper)])
        run(["codesign", "--verify", "--strict",
             "-R", "=" + developer_id_requirement(helper_id, args.team_id), str(helper)])

        plist = root / "sample.plist"
        stderr = root / "helper.log"
        plist.write_bytes(plistlib.dumps({
            "Label": helper_id,
            "ProgramArguments": [str(helper_binary), sample_arg],
            "MachServices": {service: True},
            "StandardErrorPath": str(stderr),
        }))
        domain = f"gui/{os.getuid()}"
        run(["launchctl", "bootstrap", domain, str(plist)])
        try:
            executable = reviewer / "Contents" / "MacOS" / "ShieldReviewerCandidateApp"
            run([str(executable), sample_arg])
        finally:
            if stderr.exists() and stderr.stat().st_size:
                print(stderr.read_text(errors="replace"), file=sys.stderr, end="")
            run(["launchctl", "bootout", f"{domain}/{helper_id}"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, required=True)
    parser.add_argument("--team-id", required=True)
    parser.add_argument("--identity", required=True)
    args = parser.parse_args()
    try:
        exercise(args)
    except subprocess.CalledProcessError as error:
        if error.returncode == 2 and error.cmd[-1] == "--signed-local-sample":
            return
        raise


if __name__ == "__main__":
    main()
