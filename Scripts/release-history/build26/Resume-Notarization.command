#!/bin/bash
set -euo pipefail
submission='2ddce196-aa63-4ccc-bb7f-459ed3cfc274'
profile='ScreenplayOS-Notary'
stage='/private/tmp/screenplay-notarize26.5o8cbN'
app="$stage/ScreenplayOS.app"
release_dir='/Users/ericwatson/Documents/Codex/2026-09-11/referenced-chatgpt-conversation-this-is-an-3/outputs/ScreenplayOS-notarized26'
[[ -d "$app" ]] || { echo 'Original signed app is missing. Stop and tell Codex.'; exit 1; }
mkdir -p "$release_dir"
exec > >(tee -a "$release_dir/notarization-resume.log") 2>&1
codesign --verify --deep --strict "$app"
echo "Resuming existing Apple submission: $submission"
xcrun notarytool wait "$submission" --keychain-profile "$profile" --timeout 30m
xcrun notarytool info "$submission" --keychain-profile "$profile" --output-format json > "$stage/status.json"
python3 - "$stage/status.json" <<'CHECK'
import json,sys
status=json.load(open(sys.argv[1]))
if status.get('status') != 'Accepted':
    raise SystemExit('Apple status: '+str(status.get('status'))+'. Stop and share the status with Codex.')
CHECK
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
archive='ScreenplayOS-0.1.3-build26-notarized.zip'
[[ ! -e "$release_dir/$archive" ]] || { echo 'Verified release archive already exists.'; exit 0; }
ditto -c -k --keepParent "$app" "$stage/$archive"
cp "$stage/$archive" "$release_dir/$archive"
shasum -a 256 "$release_dir/$archive" > "$release_dir/SHA256SUMS.txt"
echo 'SUCCESS: Signed, notarized, stapled, and Gatekeeper-verified.'
echo "Download archive: $release_dir/$archive"
