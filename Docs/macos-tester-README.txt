ScreenplayOS — experimental Mac tester build

Requires macOS 13 or later. Universal app: Apple Silicon and Intel.
No Terminal, Xcode, Python installation, or developer account is needed to launch
and use the ordinary editor. Experimental legacy conversion still requires Python.

1. Sign into GitHub. Open the successful "macOS Tester App" workflow run linked
   from the draft packaging PR. Under Artifacts, download
   ScreenplayOS-macOS-universal-tester-<full source commit>.
2. Double-click the downloaded artifact ZIP. Inside it, double-click
   ScreenplayOS-macOS-universal-tester.zip to extract ScreenplayOS.app.
3. Keep this tester in a separate folder (do not replace another installed copy).
   Quit other ScreenplayOS copies, then double-click ScreenplayOS.app.
4. This build has no Developer ID signature and is NOT notarized. If macOS blocks
   it as an unidentified developer, and you trust this exact build, open System
   Settings > Privacy & Security > Open Anyway after the first launch attempt.
   Confirm Open. Future launches use a normal double-click. Managed Macs may
   prohibit this exception. Do not disable Gatekeeper or use Terminal bypasses.
   Apple's explanation: https://support.apple.com/en-us/102445

"Unsigned tester" here means no verified developer identity. It uses an ad-hoc
signature to seal the bundle and support Apple Silicon execution. This is not
Developer ID signing, Apple notarization, malware certification, or a public release.
A smooth public distribution requires a separately authorized Developer ID signed,
hardened-runtime, notarized and stapled build. No production credentials are used.

Use disposable projects and synthetic media. The tester uses a separate bundle
identifier, but some existing application-support folders are shared with other
ScreenplayOS builds. It is not a separate data sandbox.

Explore Outline, Script, Shot, Boards and Edit, save/reopen a disposable project,
and inspect paused video frames. Continuous native video playback, synchronized
native-editor audio and mixed video/still export remain disabled/unverified.
No new media capability is enabled by packaging.

BUILD-INFO.txt records the source commit and build tools. SHA256SUMS.txt records
the inner app ZIP checksum. CI verifies the extracted app, both architecture slices,
resources, signature and a LaunchServices window launch on the runner's architecture.
This is not full manual workflow acceptance or a Gatekeeper/notarization test.
