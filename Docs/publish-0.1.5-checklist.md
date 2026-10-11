# ScreenplayOS 0.1.5 build 28 publish checklist

Use this checklist from the `ScreenplayOS_Starter` repository root. Stop at the first unexpected result. The release source is commit `2299e5d542f27196ab19863bb76d19f427b02a25`; the release DMG is `../ScreenplayOS-0.1.5-build28-signed/ScreenplayOS-0.1.5.dmg`; its expected SHA-256 is `ef85fd041103f768876926857c0103eb455946ee5e25a163945311a54d9349c2`.

## 1. Complete the owner GUI acceptance checks

Use the signed app from a disposable copy of the release DMG. Do not overwrite the installed app. Use a disposable copy of every screenplay because ScreenplayOS autosaves.

Prepare the test directory and legacy document:

```sh
GUI_CHECK_DIR="$(mktemp -d /private/tmp/screenplayos-0.1.5-gui.XXXXXX)"
cp Tests/Fixtures/Defenders_of_Cat_Island.open-screenplay.json "$GUI_CHECK_DIR/"
printf 'GUI check directory: %s\n' "$GUI_CHECK_DIR"
```

Expected result: the command prints a new temporary directory containing `Defenders_of_Cat_Island.open-screenplay.json`.

1. Mount `../ScreenplayOS-0.1.5-build28-signed/ScreenplayOS-0.1.5.dmg`, copy `ScreenplayOS.app` from it into the printed temporary directory, and launch that copied app.
2. In the app, open the copied `Defenders_of_Cat_Island.open-screenplay.json`. Confirm it opens normally **in place** and no “opened as a copy” message appears.
3. Make a harmless edit and wait for autosave. In Finder, confirm the filename is still exactly `Defenders_of_Cat_Island.open-screenplay.json` and no replacement/copy document appeared.
4. Create a new document and use Save As in the same temporary directory. Confirm the proposed filename ends in `.screenplayos.json`. Save it, close it, and reopen it.
5. Quit ScreenplayOS. In Finder, double-click both the legacy `.open-screenplay.json` document and the new `.screenplayos.json` document. Each must reopen in ScreenplayOS without an error or copy warning.

After the app is closed, verify both files and the new format identifier:

```sh
find "$GUI_CHECK_DIR" -maxdepth 1 -type f \
  \( -name '*.open-screenplay.json' -o -name '*.screenplayos.json' \) -print
python3 - "$GUI_CHECK_DIR"/*.screenplayos.json <<'PY'
import json
import sys
from pathlib import Path

for name in sys.argv[1:]:
    path = Path(name)
    document = json.loads(path.read_text())
    assert document.get("format") == "screenplayos", (path, document.get("format"))
    print(f"PASS {path.name}: format=screenplayos")
PY
```

Expected result: the original legacy filename is present, the new filename ends in `.screenplayos.json`, and Python prints `PASS ...: format=screenplayos`. Record the completed manual checks before continuing.

## 2. Stage and upload the 0.1.5 DMG

Verify the local artifact before copying it:

```sh
EXPECTED_DMG_SHA256='ef85fd041103f768876926857c0103eb455946ee5e25a163945311a54d9349c2'
DMG='../ScreenplayOS-0.1.5-build28-signed/ScreenplayOS-0.1.5.dmg'
printf '%s  %s\n' "$EXPECTED_DMG_SHA256" "$DMG" | shasum -a 256 -c -
```

Expected result:

```text
../ScreenplayOS-0.1.5-build28-signed/ScreenplayOS-0.1.5.dmg: OK
```

Copy it into the existing Sites source checkout while retaining the 0.1.4 DMG:

```sh
SITE_DIST='/Users/ericwatson/Documents/Codex/2026-10-08/we-are-turning-screenplayos-into-a/work/screenplayos-site/dist'
test -f "$SITE_DIST/downloads/ScreenplayOS-0.1.4.dmg"
install -m 0644 "$DMG" "$SITE_DIST/downloads/ScreenplayOS-0.1.5.dmg"
shasum -a 256 "$SITE_DIST/downloads/ScreenplayOS-0.1.5.dmg"
```

Expected result: `test` is silent and succeeds; `shasum` prints `ef85fd041103f768876926857c0103eb455946ee5e25a163945311a54d9349c2` for the staged 0.1.5 DMG. In the existing Sites project `appgprj_6ac84cdf191c81919cf41a7d0572cfab`, save and deploy a new version of this exact static checkout to its existing public audience. Do not create another Site or alter DNS, mail, Buttondown, or the signup Worker.

Verify the public object:

```sh
DMG_URL='https://screenplayos.com/downloads/ScreenplayOS-0.1.5.dmg'
curl -fsSI "$DMG_URL"
PUBLIC_DMG="$(mktemp /private/tmp/ScreenplayOS-0.1.5-public.XXXXXX.dmg)"
curl -fL "$DMG_URL" -o "$PUBLIC_DMG"
printf '%s  %s\n' "$EXPECTED_DMG_SHA256" "$PUBLIC_DMG" | shasum -a 256 -c -
```

Expected result: the headers contain an HTTP `200` final response; the download completes; and `shasum` prints `<temporary path>: OK`. Do not continue if the response is not 200 or the checksum differs.

## 3. Publish the release configuration and prepare the public site

Change only `published` in `Website/release.json` from `false` to `true`. Confirm the result:

```sh
python3 - <<'PY'
import json
from pathlib import Path

path = Path("Website/release.json")
release = json.loads(path.read_text())
assert release == {
    "version": "0.1.5",
    "build": 28,
    "releaseDate": "2026-10-11",
    "published": False,
    "downloadUrl": "https://screenplayos.com/downloads/ScreenplayOS-0.1.5.dmg",
}, release
release["published"] = True
path.write_text(json.dumps(release, indent=2) + "\n")
PY
git diff -- Website/release.json
```

Expected diff:

```diff
-  "published": false,
+  "published": true,
```

Update the visible install section in `Website/index.html` from build 27 to build 28 and from the 0.1.4 filename/checksum to the 0.1.5 filename/checksum:

```sh
python3 - <<'PY'
from pathlib import Path

path = Path("Website/index.html")
text = path.read_text()
replacements = {
    "Version 0.1.4 (27)": "Version 0.1.5 (28)",
    "ScreenplayOS-0.1.4.dmg": "ScreenplayOS-0.1.5.dmg",
    "9eaf5b2b40f1df15918963287dc773513411afc8187e63f4d3bc4006c03f2e41":
        "ef85fd041103f768876926857c0103eb455946ee5e25a163945311a54d9349c2",
}
for old, new in replacements.items():
    assert text.count(old) == 1, (old, text.count(old))
    text = text.replace(old, new)
path.write_text(text)
PY
rg -n 'Version 0\.1\.5 \(28\)|ScreenplayOS-0\.1\.5\.dmg|ef85fd041103f768876926857c0103eb455946ee5e25a163945311a54d9349c2' Website/index.html
```

Expected result: three matching values appear in the install section: `Version 0.1.5 (28)`, `ScreenplayOS-0.1.5.dmg`, and the expected SHA-256.

Build the public site into the existing Sites checkout:

```sh
python3 Website/build-public.py "$SITE_DIST"
python3 - "$SITE_DIST/release.json" <<'PY'
import json
import sys

release = json.load(open(sys.argv[1]))
assert release == {
    "version": "0.1.5",
    "build": 28,
    "releaseDate": "2026-10-11",
}, release
assert "downloadUrl" not in release
assert "published" not in release
print("PASS: browser-facing release.json contains public metadata only")
PY
rg -n 'Version 0\.1\.5 \(28\)|ScreenplayOS-0\.1\.5\.dmg|ef85fd041103f768876926857c0103eb455946ee5e25a163945311a54d9349c2' "$SITE_DIST/index.html"
```

Expected result: `build-public.py` reports that it prepared the destination without the download URL; Python prints its `PASS` line; and the staged page contains the new version, filename, and checksum. Save and deploy a new Sites version from this exact checkout to the existing public audience. Record the saved version ID, deployment ID, and deployment time.

## 4. Verify the deployed root and `/index.html`

Open both `https://screenplayos.com/` and `https://screenplayos.com/index.html` in a private browser window. Both must resolve to a page showing `Version 0.1.5 (28)`, `ScreenplayOS-0.1.5.dmg`, and the new checksum.

Run the same check from Terminal, following redirects:

```sh
for url in 'https://screenplayos.com/' 'https://screenplayos.com/index.html'; do
  printf '%s\n' "$url"
  body="$(curl -fsSL "$url")" || exit 1
  printf '%s' "$body" | grep -F 'Version 0.1.5 (28)' >/dev/null || exit 1
  printf '%s' "$body" | grep -F 'ScreenplayOS-0.1.5.dmg' >/dev/null || exit 1
  printf '%s' "$body" | grep -F 'ef85fd041103f768876926857c0103eb455946ee5e25a163945311a54d9349c2' >/dev/null || exit 1
  echo 'PASS'
done
```

Expected result: each URL is followed by `PASS`. If either page is stale, hard-refresh and retry in a private window and from another network. The available Sites controls expose no cache-purge command. If the Sites-generated production URL is current but the custom-domain root remains stale, ask OpenAI Support at `help.openai.com` to purge/revalidate `https://screenplayos.com/` for project `appgprj_6ac84cdf191c81919cf41a7d0572cfab`; provide the version ID, deployment ID/time, stale/current markers, and response headers. Do not change DNS to address an HTML cache.

## 5. Update and verify the welcome email

`email/E1-welcome.md` reads `{{version}}` and `{{download_url}}` from `Website/release.json`; it does not hardcode a release number. Render it from the now-published configuration:

```sh
python3 email/render.py email/E1-welcome.md > /private/tmp/ScreenplayOS-E1-welcome-0.1.5.txt
rg -n 'ScreenplayOS 0\.1\.5|https://screenplayos\.com/downloads/ScreenplayOS-0\.1\.5\.dmg' /private/tmp/ScreenplayOS-E1-welcome-0.1.5.txt
```

Expected result: the rendered welcome email contains `ScreenplayOS 0.1.5` and the 0.1.5 DMG URL. Update the post-confirmation welcome/redirect in Buttondown from the rendered values, preserving double opt-in, the postal footer, unsubscribe behavior, and existing tracking settings. Send no campaign as part of this release procedure. Verify the saved configuration visibly in Buttondown.

## 6. Commit, tag, and push the release source

First inspect the final source changes and commit the approved release configuration, visible install copy, and any approved tracked email changes. Do not include generated site output, downloaded artifacts, credentials, or unrelated files:

```sh
git status --short
git diff -- Website/release.json Website/index.html email/
git add Website/release.json Website/index.html
git commit -m "Publish ScreenplayOS 0.1.5"
```

Expected result: the commit succeeds and contains only the reviewed release-source changes. Confirm that commit `2299e5d542f27196ab19863bb76d19f427b02a25` is an ancestor, then tag the exact verified artifact source commit requested for this release and push the branch and tag:

```sh
git merge-base --is-ancestor 2299e5d542f27196ab19863bb76d19f427b02a25 HEAD
git tag -a v0.1.5-build28 2299e5d542f27196ab19863bb76d19f427b02a25 -m "ScreenplayOS 0.1.5 build 28"
git show --no-patch --decorate v0.1.5-build28
git push origin HEAD
git push origin v0.1.5-build28
```

Expected result: the ancestry check is silent and exits successfully; `git show` identifies tag `v0.1.5-build28` at `2299e5d`; both pushes succeed. The tag must point to `2299e5d`, not the later publication-config commit.

## 7. Roll back if 0.1.5 fails after publication

Leave `ScreenplayOS-0.1.4.dmg` at `/downloads/` throughout release and verification. To withdraw 0.1.5 from the release configuration, set `published` back to `false`, rebuild the static site, save a new Sites version, and deploy it:

```sh
python3 - <<'PY'
import json
from pathlib import Path

path = Path("Website/release.json")
release = json.loads(path.read_text())
assert release["version"] == "0.1.5" and release["build"] == 28, release
release["published"] = False
path.write_text(json.dumps(release, indent=2) + "\n")
PY
python3 Website/build-public.py "$SITE_DIST"
test -f "$SITE_DIST/downloads/ScreenplayOS-0.1.4.dmg"
test -f "$SITE_DIST/downloads/ScreenplayOS-0.1.5.dmg"
```

Expected result: both DMGs remain present and `Website/release.json` contains `"published": false`. Because the current browser-facing site is static and omits `published`, also restore the last known-good 0.1.4 install/version/checksum copy in `Website/index.html`, run `Website/build-public.py` again, then save and deploy that rollback Sites version. Verify the private-window and `curl` checks show 0.1.4. Do not delete either DMG while diagnosing the failure.

## 8. Test command rule

Run every test, including a targeted test, through `Scripts/test.sh`. It sets `CLANG_MODULE_CACHE_PATH` and `SWIFTPM_MODULECACHE_OVERRIDE`; a bare `swift test` can fail for environmental reasons and is not an accepted release check.

Full suite:

```sh
Scripts/test.sh
```

Targeted Swift test:

```sh
Scripts/test.sh --filter 'ExactTestCaseOrMethodName'
```

Expected result: the wrapper reports the requested test run as passing. Never substitute bare `swift test`.
