# Direct macOS distribution

ScreenplayOS is a Swift Package that `Scripts/package-app.sh` wraps as a Mac app. `Website/release.json` is the single release configuration: version, build, release date, publication state, and direct DMG URL. The site reads that file at page load. Version `0.1.4` build `27` is an **unpublished candidate**, not an announced release.

## Local unsigned review

From the repository root, run:

```sh
python3 -m venv .build/release-venv
.build/release-venv/bin/python -m pip install -r Scripts/requirements-release.txt
export SCREENPLAYOS_DMG_PYTHON="$PWD/.build/release-venv/bin/python"
./Scripts/release.py --dry-run --unsigned
./Scripts/release.py --unsigned --arch arm64 --output /path/to/empty/review-output
```

`--arch universal` builds Apple Silicon plus Intel; `--arch x86_64` builds Intel only. The pinned [dmgbuild](https://dmgbuild.readthedocs.io/en/latest/) package writes the Finder layout without a GUI session. An unsigned run allows uncommitted source and records `sourceDirty` in the manifest. It creates an ad-hoc signed app inside a DMG and ZIP, plus release notes, SHA-256 checksums, and a manifest. It is for local review, not public downloads. The script never replaces the installed app or prior build artifacts, and refuses a nonempty output directory. `./Scripts/test.sh` runs the repository test suite.

## Signed public release

Requires a paid Apple Developer Program account, a **Developer ID Application** certificate and private key installed in the signing Mac's keychain, and notarytool credentials for the same Apple Developer team. An App Store distribution certificate is not a substitute. Store an App Store Connect API key or Apple ID app-specific password in a named notarytool keychain profile, following Apple's `xcrun notarytool store-credentials` prompts. Do not put the password, API private key, or profile contents in this repository.

Example profile setup with an Apple ID and app-specific password (run interactively; enter the password only into Apple's prompt):

```sh
xcrun notarytool store-credentials screenplayos-notary --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
xcrun notarytool history --keychain-profile screenplayos-notary
```

For an App Store Connect API key, use `xcrun notarytool store-credentials screenplayos-notary --key /secure/path/AuthKey_ID.p8 --key-id KEY_ID --issuer ISSUER_ID`. Keep the `.p8` outside the repository. Verify the identity with `security find-identity -v -p codesigning`.

Commit and test the **exact** source to release. The signed path rejects any modified or untracked file in the checkout. Set the identity to the exact `Developer ID Application: ...` name shown by Keychain, and set the saved profile name:

```sh
export SCREENPLAYOS_SIGNING_IDENTITY='Developer ID Application: NAME (TEAMID)'
export SCREENPLAYOS_NOTARY_PROFILE='screenplayos-notary'
./Scripts/release.py --dry-run
./Scripts/release.py --arch universal --output /path/to/empty/public-output
```

The script builds Release, signs the app with hardened runtime and timestamp, submits the app to Apple, staples and validates its ticket, then builds and signs the DMG with an Applications shortcut and deterministic Finder layout. It mounts and inspects the DMG, submits that DMG for notarization, staples and validates the DMG ticket, and writes the ZIP, checksums, notes, and manifest. No credential is created or guessed by the script. Keep the generated manifest and checksums beside the downloadable artifacts.

## Website and hosting

The public page is hosted by **Sites** (project `appgprj_6ac84cdf191c81919cf41a7d0572cfab`); Hover remains the registrar and DNS provider. `Website/` in this repository is the canonical website source. The Sites source checkout contains only a copy of those public files under `dist/`, with `.openai/hosting.json` setting `static.directory` to `dist` and the project ID above. Sync changes from `Website/` into that checkout, then save and deploy a new Sites version. Do not copy app source, review builds, signing material, or private files into the site checkout.

The public download is still disabled. Before enabling it, confirm that the chosen delivery setup supports the signed DMG and stable direct links under `/downloads/`. Upload the signed `ScreenplayOS-<version>.dmg` there, with the ZIP, checksums, release notes, and manifest available nearby. If Sites cannot serve the DMG at that path, configure object storage/CDN behind a `/downloads/*` route on **screenplayos.com**; the public button must retain the same-domain URL. Test the final HTTPS URL and downloaded SHA-256 before enabling it.

For each release: edit **only** `Website/release.json` for version, monotonically increasing build, real release date, and matching `https://screenplayos.com/downloads/ScreenplayOS-<version>.dmg`; build the artifacts; upload them; verify the public URL and checksum; then change `published` to `true` and deploy the site. The button stays inactive while `published` is `false`. The current contact link uses `ericjasonwatson@gmail.com` until a dedicated mailbox is configured. The site has no analytics scripts or forms; review host logs and privacy copy before launch.

The Sites custom domains are `screenplayos.com` and `www.screenplayos.com`. Hover has apex `A` records `162.159.143.30` and `172.66.3.26`, a `www` CNAME to `custom-domains.chatgpt.site`, and the TXT ownership/certificate records assigned by Sites. The old wildcard `A` record remains for otherwise unused subdomains. Check both custom-domain and HTTPS status in Sites after DNS propagates. Before app launch, configure a canonical redirect if Sites offers one, and establish the same-domain `/downloads/` route. The secondary GitHub link currently points to the public profile because the development repository is private.

Changing the bundle ID from `dev.screenplayos.prototype` to `com.screenplayos.app` gives the app a new preferences domain. On first production launch, known recent-document and UI/AI provider preferences are copied only when their new-domain keys are absent. Existing document files, `Application Support/ScreenplayOS/Recovery`, and the established Keychain service remain in place. No document migration is performed.
