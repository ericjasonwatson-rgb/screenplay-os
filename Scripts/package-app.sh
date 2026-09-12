#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PWD/.build/swift-cache"
swift build --disable-sandbox --cache-path "$PWD/.build/swift-cache" --product ScreenplayOS
binary_dir="$(swift build --disable-sandbox --cache-path "$PWD/.build/swift-cache" --show-bin-path)"
app_destination="${1:-$PWD/../ScreenplayOS.app}"
python3 - "$binary_dir/ScreenplayOS" "$app_destination" <<'PY'
import pathlib, plistlib, shutil, subprocess, sys
source, app = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
(app / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
# Replace the executable inode so packaging never writes into a running binary.
temporary = app / 'Contents/MacOS/ScreenplayOS.new'
shutil.copy2(source, temporary)
temporary.replace(app / 'Contents/MacOS/ScreenplayOS')
resources = app / 'Contents/Resources'
resources.mkdir(parents=True, exist_ok=True)
# Convert the supplied artwork to standard macOS icon sizes without redrawing it.
logo = pathlib.Path('Sources/ScreenplayOSApp/Resources/ScreenplayOSLogo.png')
shutil.copy2(logo, resources / 'ScreenplayOSLogo.png')
iconset = pathlib.Path('.build/ScreenplayOS.iconset')
iconset.mkdir(parents=True, exist_ok=True)
for points in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        pixels = points * scale
        name = f'icon_{points}x{points}' + ('@2x' if scale == 2 else '') + '.png'
        subprocess.run(['sips', '-z', str(pixels), str(pixels), str(logo), '--out', str(iconset / name)], check=True, stdout=subprocess.DEVNULL)
subprocess.run(['iconutil', '-c', 'icns', str(iconset), '-o', str(resources / 'ScreenplayOS.icns')], check=True)
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
}))
print(app.resolve())
PY
