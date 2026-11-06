#!/usr/bin/env python3
"""Cross-process durable-claim regression. Synthetic assets only; no network."""
import concurrent.futures
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

if len(sys.argv) != 2:
    raise SystemExit("usage: cross_process_approval.py <swift-build-bin-directory>")
binary = pathlib.Path(sys.argv[1]) / "ShieldDurableApprovalFixture"
assert binary.is_file(), "CI fixture executable missing"

def call(*args):
    return subprocess.run([str(binary), *map(str, args)], text=True,
                          capture_output=True, timeout=20)

def expect(status, result, text):
    if result.returncode != status or result.stdout.strip() != text:
        raise AssertionError(
            "expected status %d %s; got %d stdout=%r stderr=%r" %
            (status, text, result.returncode, result.stdout, result.stderr)
        )

with tempfile.TemporaryDirectory(prefix="cips-ci-approval-",
                                 dir=str(pathlib.Path.home().resolve())) as directory:
    root = pathlib.Path(directory)
    os.chmod(root, 0o700)
    db = root / "claims.sqlite"

    def mint(uid, name):
        response = call("sign", uid)
        assert response.returncode == 0, response.stderr
        data = json.loads(response.stdout)
        fixture = root / name
        fixture.write_text(json.dumps(data), encoding="utf-8")
        os.chmod(fixture, 0o600)
        return fixture

    a = mint("20000000-0000-0000-0000-000000000002", "a.json")
    expect(0, call("bootstrap", db), "BOOTSTRAPPED")
    expect(0, call("claim", db, a), "CLAIMED")
    # Every run creates a fresh OS process, verifier and SQLite connection.
    expect(42, call("claim", db, a), "DUPLICATE")

    b = mint("20000000-0000-0000-0000-000000000003", "b.json")
    # Simultaneously invoke 8 independent processes against the same ID.
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        responses = list(pool.map(lambda _: call("claim", db, b), range(8)))
    assert sum(x.returncode == 0 and x.stdout.strip() == "CLAIMED" for x in responses) == 1, [
        (x.returncode, x.stdout, x.stderr) for x in responses
    ]
    assert sum(x.returncode == 42 and x.stdout.strip() == "DUPLICATE" for x in responses) == 7, [
        (x.returncode, x.stdout, x.stderr) for x in responses
    ]

    c = mint("20000000-0000-0000-0000-000000000004", "c.json")
    # Tamper with signed request identifier but leave the signature unchanged.
    data = json.loads(c.read_text(encoding="utf-8"))
    data["requestID"] = "20000000-0000-0000-0000-000000000005"
    tampered = root / "tampered.json"
    tampered.write_text(json.dumps(data), encoding="utf-8")
    os.chmod(tampered, 0o600)
    expect(42, call("claim", db, tampered), "DENIED")
    # Tampered signature must not spend a separate, valid request ID.
    d = mint("20000000-0000-0000-0000-000000000005", "d.json")
    expect(0, call("claim", db, d), "CLAIMED")

    # A missing history must NEVER silently start a new database.
    db.unlink()
    assert call("claim", db, a).returncode == 42
    assert not db.exists()

print("PASS: separate-process restart, eight-way concurrency, tamper and missing-history checks")
