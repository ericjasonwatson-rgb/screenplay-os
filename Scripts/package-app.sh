#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/.build/swift-cache"
scratch_path="${SCREENPLAYOS_SCRATCH_PATH:-$PWD/.build}"
configuration="${SCREENPLAYOS_BUILD_CONFIGURATION:-release}"
# Default to Apple Silicon; use universal for Apple Silicon plus Intel.
architecture="${SCREENPLAYOS_BUILD_ARCH:-arm64}"
case "$architecture" in
    arm64|x86_64|universal) ;;
    *) echo "Unsupported architecture: $architecture" >&2; exit 1 ;;
esac
identity="${SCREENPLAYOS_SIGNING_IDENTITY:--}"
notary_profile="${SCREENPLAYOS_NOTARY_PROFILE:-}"
if [[ -n "$notary_profile" && "$identity" == "-" ]]; then
    echo "Notarization requires SCREENPLAYOS_SIGNING_IDENTITY (Developer ID Application)." >&2
    exit 1
fi
# A build must be traceable to the exact source it contains. Refuse uncommitted
# source unless explicitly allowed, and mark such builds "-dirty" in the bundle.
source_changes="$(git status --porcelain --untracked-files=all)"
export SCREENPLAYOS_SOURCE_DIRTY=0
if [[ -n "$source_changes" ]]; then
    if [[ "$identity" != "-" || "${SCREENPLAYOS_ALLOW_DIRTY:-0}" != "1" ]]; then
        echo "Uncommitted source changes; commit them before packaging:" >&2
        echo "$source_changes" >&2
        echo "(Local ad-hoc builds only: set SCREENPLAYOS_ALLOW_DIRTY=1 to override.)" >&2
        exit 1
    fi
    export SCREENPLAYOS_SOURCE_DIRTY=1
fi
# Signed builds are distributed; their version must be stated, never defaulted.
if [[ "$identity" != "-" && ( -z "${SCREENPLAYOS_APP_VERSION:-}" || -z "${SCREENPLAYOS_BUILD_NUMBER:-}" ) ]]; then
    echo "Signed builds require SCREENPLAYOS_APP_VERSION and SCREENPLAYOS_BUILD_NUMBER." >&2
    exit 1
fi
app_destination="${1:-$PWD/../ScreenplayOS.app}"
build_stage="$(mktemp -d)"
trap 'rm -rf "$build_stage"' EXIT
if [[ "$architecture" == "universal" ]]; then
    binaries=()
    for arch in arm64 x86_64; do
        swift build --arch "$arch" --configuration "$configuration" --disable-sandbox --scratch-path "$scratch_path" --cache-path "$PWD/.build/swift-cache" --product ScreenplayOS
        binary_dir="$(swift build --arch "$arch" --configuration "$configuration" --disable-sandbox --scratch-path "$scratch_path" --cache-path "$PWD/.build/swift-cache" --show-bin-path)"
        binaries+=("$binary_dir/ScreenplayOS")
    done
    binary_source="$build_stage/ScreenplayOS-universal"
    lipo -create "${binaries[@]}" -output "$binary_source"
else
    swift build --arch "$architecture" --configuration "$configuration" --disable-sandbox --scratch-path "$scratch_path" --cache-path "$PWD/.build/swift-cache" --product ScreenplayOS
    binary_dir="$(swift build --arch "$architecture" --configuration "$configuration" --disable-sandbox --scratch-path "$scratch_path" --cache-path "$PWD/.build/swift-cache" --show-bin-path)"
    binary_source="$binary_dir/ScreenplayOS"
fi
staged_app="$build_stage/ScreenplayOS.app"
python3 - "$binary_source" "$staged_app" "$configuration" <<'PY'
import os, pathlib, plistlib, re, shutil, subprocess, sys
source, app = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
version = os.environ.get('SCREENPLAYOS_APP_VERSION', '0.1')
build = os.environ.get('SCREENPLAYOS_BUILD_NUMBER', '1')
if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', version) or not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', build):
    raise SystemExit('App version and build number must contain one to three numeric components.')
(app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
# Replace the executable inode so packaging never writes into a running binary.
temporary = app / 'Contents/MacOS/ScreenplayOS.new'
shutil.copy2(source, temporary)
temporary.replace(app / 'Contents/MacOS/ScreenplayOS')
resources = app / 'Contents/Resources'
resources.mkdir(parents=True, exist_ok=True)
# Preserve the supplied PNG and its prebuilt standard macOS icon representations.
branding = pathlib.Path('Sources/ScreenplayOSApp/Resources')
shutil.copy2(branding / 'ScreenplayOSLogo.png', resources / 'ScreenplayOSLogo.png')
shutil.copy2(branding / 'ScreenplayOS.icns', resources / 'ScreenplayOS.icns')
revision = subprocess.check_output(['git', 'rev-parse', '--short', 'HEAD'], text=True).strip()
if os.environ.get('SCREENPLAYOS_SOURCE_DIRTY') == '1':
    revision += '-dirty'
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleExecutable': 'ScreenplayOS',
    'CFBundleIdentifier': 'com.screenplayos.app',
    'CFBundleName': 'ScreenplayOS',
    'CFBundleIconFile': 'ScreenplayOS.icns',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': version,
    'CFBundleVersion': build,
    'LSMinimumSystemVersion': '13.0',
    'NSHighResolutionCapable': True,
    'ScreenplayOSRevision': revision,
    'ScreenplayOSBuildConfiguration': sys.argv[3],
}))
print(app.resolve())
PY

# Sign the completed bundle, not just Swift's linker-signed executable.
# Finder/iCloud metadata copied with source assets can prevent code signing.
xattr -cr "$staged_app"
if [[ "$identity" == "-" ]]; then
    codesign --force --sign - "$staged_app"
    echo "Local ad-hoc build: not notarized or approved for downloaded distribution." >&2
else
    codesign --force --sign "$identity" --options runtime --timestamp "$staged_app"
fi
codesign --verify --deep --strict --verbose=2 "$staged_app"

# A keychain profile must be configured by the developer in advance.
if [[ -n "$notary_profile" ]]; then
    notarization_dir="$build_stage/notarization"
    mkdir -p "$notarization_dir"
    ditto -c -k --keepParent "$staged_app" "$notarization_dir/ScreenplayOS.zip"
    xcrun notarytool submit "$notarization_dir/ScreenplayOS.zip" --keychain-profile "$notary_profile" --wait
    xcrun stapler staple "$staged_app"
    xcrun stapler validate "$staged_app"
    spctl --assess --type execute --verbose=2 "$staged_app"
fi

# Preserve the verified bundle and avoid copying resource forks/Finder metadata.
# Replace the bundle directory instead of overwriting a signed/running executable.
if [[ -e "$app_destination" ]]; then
    mv "$app_destination" "$build_stage/previous.app"
fi
if ! python3 - "$staged_app" "$app_destination" <<'COPY'
import pathlib, shutil, sys
source, destination = map(pathlib.Path, sys.argv[1:])
# Copy file contents only: Finder metadata and ACLs are not part of the code seal.
shutil.copytree(source, destination, copy_function=shutil.copyfile)
(destination / 'Contents/MacOS/ScreenplayOS').chmod(0o755)
COPY
then
    if [[ -e "$build_stage/previous.app" ]]; then
        mv "$app_destination" "$build_stage/incomplete.app"
        mv "$build_stage/previous.app" "$app_destination"
    fi
    exit 1
fi
xattr -cr "$app_destination"
codesign --verify --deep --strict --verbose=2 "$app_destination"
# Only numbered review artifacts in this checkout's outputs are eligible.
# Keep the newest archive as a usable download/rollback copy.
if [[ "${SCREENPLAYOS_SKIP_REVIEW_CLEANUP:-0}" != "1" ]]; then
    if ! python3 Scripts/cleanup-build-artifacts.py "$app_destination" --apply; then
        echo "Warning: review-artifact cleanup failed; the verified app is ready." >&2
    fi
fi
echo "$app_destination"
