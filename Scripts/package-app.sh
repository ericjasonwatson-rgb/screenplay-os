#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/.build/swift-cache"
configuration="${SCREENPLAYOS_BUILD_CONFIGURATION:-release}"
swift build --configuration "$configuration" --disable-sandbox --cache-path "$PWD/.build/swift-cache" --product ScreenplayOS
binary_dir="$(swift build --configuration "$configuration" --disable-sandbox --cache-path "$PWD/.build/swift-cache" --show-bin-path)"
app_destination="${1:-$PWD/../ScreenplayOS.app}"
python3 - "$binary_dir/ScreenplayOS" "$app_destination" "$configuration" <<'PY'
import pathlib, plistlib, shutil, subprocess, sys
source, app = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
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
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleExecutable': 'ScreenplayOS',
    'CFBundleIdentifier': 'dev.screenplayos.prototype',
    'CFBundleName': 'ScreenplayOS',
    'CFBundleIconFile': 'ScreenplayOS.icns',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.1',
    'CFBundleVersion': '1',
    'LSMinimumSystemVersion': '13.0',
    'NSHighResolutionCapable': True,
    'ScreenplayOSRevision': revision,
    'ScreenplayOSBuildConfiguration': sys.argv[3],
}))
print(app.resolve())
PY
