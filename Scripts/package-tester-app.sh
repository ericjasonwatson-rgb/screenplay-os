#!/bin/bash
# Reproducible recipe for a credential-free, universal local tester archive.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname -s)" == Darwin ]] || { echo 'macOS is required.' >&2; exit 1; }
if [[ -n "${SCREENPLAYOS_NOTARY_PROFILE:-}" || "${SCREENPLAYOS_SIGNING_IDENTITY:--}" != '-' ]]; then
    echo 'Tester packaging refuses signing identities and notarization profiles.' >&2
    exit 1
fi
export SCREENPLAYOS_TESTER_BUILD=1 SCREENPLAYOS_SIGNING_IDENTITY=-
export SCREENPLAYOS_BUILD_ARCH=universal SCREENPLAYOS_BUILD_CONFIGURATION=release
export SCREENPLAYOS_ALLOW_DIRTY=0 SCREENPLAYOS_SKIP_REVIEW_CLEANUP=1
export SCREENPLAYOS_APP_VERSION=0.1 SCREENPLAYOS_BUILD_NUMBER=1
revision="$(git rev-parse HEAD)"
output="$PWD/dist/macos-tester/$revision"
mkdir -p "$output"
bash Scripts/package-app.sh "$output/ScreenplayOS.app"
python3 Scripts/verify-tester-app.py "$output/ScreenplayOS.app" "$revision"
cp Docs/macos-tester-README.txt "$output/READ-ME-FIRST.txt"
{
    echo "Source: $revision"
    echo 'Configuration: release; architectures: arm64 x86_64; signing: ad-hoc; notarized: no'
    swift --version
    xcodebuild -version
    sw_vers
} > "$output/BUILD-INFO.txt"
# Nest a ditto ZIP inside the Actions artifact to preserve executable permissions.
ditto -c -k --keepParent "$output/ScreenplayOS.app" "$output/ScreenplayOS-macOS-universal-tester.zip"
(cd "$output" && shasum -a 256 ScreenplayOS-macOS-universal-tester.zip > SHA256SUMS.txt)
echo "$output"
