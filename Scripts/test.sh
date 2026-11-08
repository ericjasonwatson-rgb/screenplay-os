#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYTHONDONTWRITEBYTECODE=1 python3 Scripts/test-fixture-hygiene.py
python3 Scripts/check-fixture-hygiene.py

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/LegacyInspector
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests/Packaging
node --test LicenseWorker/test/*.test.mjs

# Verify the independently authored synthetic agency examples before native tests.
PYTHONDONTWRITEBYTECODE=1 python3 Scripts/check-campaign-agency-fixtures.py --self-test --check

# Keep compiler caches inside the ignored build directory, including in Codex.
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/.build/swift-cache"

# Command Line Tools installations may omit these Swift Testing search paths.
# Full Xcode installations use SwiftPM's normal defaults.
developer_dir="$(xcode-select -p)"
testing_frameworks="$developer_dir/Library/Developer/Frameworks"
testing_libraries="$developer_dir/Library/Developer/usr/lib"
test_args=()
if [[ -d "$testing_frameworks/Testing.framework" ]]; then
    test_args+=(-Xswiftc -F -Xswiftc "$testing_frameworks")
    test_args+=(-Xlinker -rpath -Xlinker "$testing_frameworks")
    test_args+=(-Xlinker -rpath -Xlinker "$testing_libraries")
fi
configuration="${SCREENPLAYOS_BUILD_CONFIGURATION:-debug}"
test_output="$(mktemp "$PWD/.build/native-test-output.XXXXXXXX")"
trap 'rm -f "$test_output"' EXIT
swift test --configuration "$configuration" --disable-sandbox --cache-path "$PWD/.build/swift-cache" ${test_args[@]+"${test_args[@]}"} "$@" 2>&1 | tee "$test_output"
python3 Scripts/check-native-test-completion.py "$test_output"
swift run --configuration "$configuration" --disable-sandbox --cache-path "$PWD/.build/swift-cache" --skip-build screenplay-self-test
swift run --configuration "$configuration" --disable-sandbox --cache-path "$PWD/.build/swift-cache" --skip-build screenplay-inspect Tests/Fixtures/Synthetic.open-screenplay.json --json >/dev/null
swift run --configuration "$configuration" --disable-sandbox --cache-path "$PWD/.build/swift-cache" --skip-build screenplay-inspect Tests/Fixtures/Minimal.screenplayos.json --json >/dev/null
