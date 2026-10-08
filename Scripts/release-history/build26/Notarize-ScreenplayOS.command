#!/bin/bash
set -euo pipefail
source_app='/private/tmp/ScreenplayOS-build26/ScreenplayOS.app'
release_dir='/Users/ericwatson/Documents/Codex/2026-09-11/referenced-chatgpt-conversation-this-is-an-3/outputs/ScreenplayOS-notarized26'
identity='B6E2854C5196F48C89024AD256F0FAD1C722EFE2'
profile='ScreenplayOS-Notary'
[[ -d "$source_app" ]] || { echo 'Validated build 26 is missing. Stop and ask Codex to restore it.'; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$source_app/Contents/Info.plist")" == 26 ]]
[[ ! -e "$release_dir/ScreenplayOS-0.1.3-build26-notarized.zip" ]] || { echo 'Release archive already exists; stop rather than overwrite it.'; exit 1; }
mkdir -p "$release_dir"
exec > >(tee "$release_dir/notarization.log") 2>&1
xcrun notarytool history --keychain-profile "$profile"
stage="$(mktemp -d /private/tmp/screenplay-notarize26.XXXXXX)"
app="$stage/ScreenplayOS.app"
echo "Release staging: $stage"
ditto "$source_app" "$app"
xattr -cr "$app"
codesign --force --sign "$identity" --options runtime --timestamp "$app"
codesign --verify --deep --strict --verbose=2 "$app"
codesign --display --verbose=4 "$app"
ditto -c -k --keepParent "$app" "$stage/submission.zip"
xcrun notarytool submit "$stage/submission.zip" --keychain-profile "$profile" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
ditto -c -k --keepParent "$app" "$stage/ScreenplayOS-0.1.3-build26-notarized.zip"
cp "$stage/ScreenplayOS-0.1.3-build26-notarized.zip" "$release_dir/ScreenplayOS-0.1.3-build26-notarized.zip"
shasum -a 256 "$release_dir/ScreenplayOS-0.1.3-build26-notarized.zip" > "$release_dir/SHA256SUMS.txt"
echo 'SUCCESS: Signed, notarized, stapled, and Gatekeeper-verified.'
echo "Download archive: $release_dir/ScreenplayOS-0.1.3-build26-notarized.zip"
