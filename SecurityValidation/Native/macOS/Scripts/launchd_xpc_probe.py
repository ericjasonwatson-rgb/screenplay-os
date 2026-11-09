#!/usr/bin/env python3
"""Probe signed-service XPC against independently spawned client via launchd."""
import os
import pathlib
import plistlib
import subprocess
import sys
import tempfile
import time

if len(sys.argv) != 2:
    raise SystemExit("usage: launchd_xpc_probe.py <build-bin-directory>")
directory = pathlib.Path(sys.argv[1])
server = directory / "ShieldXPCProbeServer"
client = directory / "ShieldXPCProbeClient"
for item in (server, client):
    if not item.is_file():
        raise RuntimeError(f"missing {item}")
    subprocess.run(["codesign", "--force", "--sign", "-", str(item)], check=True, capture_output=True)
label = "com.example.cips.validation.probe"
services = {
    "com.example.cips.validation.control": True,
    "com.example.cips.validation.denied": True,
}
with tempfile.TemporaryDirectory(prefix="cips-launchd-") as tmp:
    plist = pathlib.Path(tmp) / "probe.plist"
    props = {
        "Label": label,
        "ProgramArguments": [str(server)],
        "MachServices": services,
        "RunAtLoad": True,
        "StandardOutPath": str(pathlib.Path(tmp) / "stdout.log"),
        "StandardErrorPath": str(pathlib.Path(tmp) / "stderr.log"),
    }
    with plist.open("wb") as stream:
        plistlib.dump(props, stream)
    uid = os.getuid()
    active_domain = None
    reasons = []
    for domain in (f"gui/{uid}", f"user/{uid}"):
        result = subprocess.run(["launchctl", "bootstrap", domain, str(plist)],
                                capture_output=True, text=True, timeout=15)
        if result.returncode == 0:
            active_domain = domain
            break
        reasons.append(f"{domain}: {result.stderr.strip()}")
    if active_domain is None:
        raise RuntimeError("No launchd domain available. Test inconclusive: " + "; ".join(reasons))
    try:
        # A positive live control is required before testing a denial.
        last = None
        for attempt in range(8):
            result = subprocess.run([str(client)], capture_output=True, text=True, timeout=25)
            last = result
            if result.returncode == 0:
                print(result.stdout)
                print("PASS: live XPC peer-signature test")
                break
            if result.returncode != 77:
                raise RuntimeError(
                    f"Live XPC test failed ({result.returncode}): " +
                    result.stdout + "\n" + result.stderr
                )
            time.sleep(0.5)
        else:
            raise RuntimeError("Live service never became ready: " +
                               (last.stderr if last else "no attempt"))
    finally:
        subprocess.run(["launchctl", "bootout", active_domain, str(plist)],
                       capture_output=True, timeout=15)
