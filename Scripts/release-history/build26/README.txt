Historical build 26 notarization scripts, copied byte-for-byte from work/apple-release.
These record the actual signing/submission and interrupted-submission resume workflow.
They contain machine-specific paths and a certificate fingerprint/profile name, not
passwords or private key material. Do not run them to build a new release. The current
packaging entry point is Scripts/package-app.sh with explicit version/build settings.

Accepted submission: 2ddce196-aa63-4ccc-bb7f-459ed3cfc274
Archive: ScreenplayOS-0.1.3-build26-notarized.zip
SHA-256: b31021b5875e139a4477c29ef6f070c2324fcdbf39ec41c9198e6cb1bcc7abdd
Source tag: v0.1.3-build26-source (458a7f9).
The original bundle stamped c1e6fcd because its source tree was then dirty.
