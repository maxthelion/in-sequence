# Developer ID Distribution

In Sequence can be packaged for other Macs from the command line. Opening Xcode
is not required for the normal distribution path, and the packaging script does
not edit `project.yml` or `SequencerAI.xcodeproj/project.pbxproj`.

## One-Time Setup

Install the Developer ID Application certificate in the login keychain.

Create a notarytool keychain profile:

```sh
xcrun notarytool store-credentials seqai-notary \
  --apple-id YOUR_APPLE_ID \
  --team-id TEAMID \
  --password APP_SPECIFIC_PASSWORD
```

`TEAMID` is the Apple Developer team identifier associated with the Developer ID
certificate. The password should be an Apple app-specific password, not the
account password.

## Build, Sign, Notarize, Staple

From a clean checkout:

```sh
scripts/package-developer-id.sh \
  --team-id TEAMID \
  --notary-profile seqai-notary
```

The script:

1. Archives the Release app with `xcodebuild archive`.
2. Exports using Developer ID signing.
3. Renames the exported bundle to `In Sequence.app`.
4. Zips the app for notarization.
5. Submits with `xcrun notarytool`.
6. Staples and validates the app notarization ticket.
7. Builds and signs a DMG containing `In Sequence.app` and an Applications
   symlink.
8. Notarizes, staples, and validates the DMG.
9. Produces a final distributable DMG under `dist/developer-id/`.

The Xcode target/scheme and bundle identifier remain `SequencerAI` /
`ai.sequencer.SequencerAI`; only the user-facing app/document names and
distributed bundle filename are `In Sequence`.

## R2 Upload

Use a dedicated distribution bucket/key rather than the visual QA screenshot
bucket. Copy `scripts/r2-distribution.env.example` to a gitignored
`scripts/distribution.r2.env`, or export the values in your shell:

```sh
R2_DISTRIBUTION_BUCKET=in-sequence-releases
R2_DISTRIBUTION_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
R2_DISTRIBUTION_ACCESS_KEY_ID=...
R2_DISTRIBUTION_SECRET_ACCESS_KEY=...
R2_REGION=auto
R2_DISTRIBUTION_PREFIX=releases/developer-id
```

Then package and upload:

```sh
scripts/package-developer-id.sh \
  --team-id TEAMID \
  --identity "Developer ID Application: Your Name (TEAMID)" \
  --notary-profile seqai-notary \
  --upload-r2
```

Use `--r2-key <key>` to set an exact object key for the final DMG.

## Useful Options

Use a specific certificate common name:

```sh
scripts/package-developer-id.sh \
  --team-id TEAMID \
  --identity "Developer ID Application: Your Name (TEAMID)" \
  --notary-profile seqai-notary
```

Create a signed but unnotarized artifact for local smoke testing:

```sh
scripts/package-developer-id.sh \
  --team-id TEAMID \
  --skip-notarize
```

Override the distributed app bundle name:

```sh
scripts/package-developer-id.sh \
  --team-id TEAMID \
  --notary-profile seqai-notary \
  --app-name "In Sequence"
```

Package from a dirty checkout only when deliberately making a throwaway build:

```sh
scripts/package-developer-id.sh \
  --team-id TEAMID \
  --notary-profile seqai-notary \
  --allow-dirty
```

## Avoiding Xcode Project Churn

Distribution should normally run through the script above. If Xcode is opened
for manual inspection or packaging, check `git status` before committing. Xcode
can rewrite `SequencerAI.xcodeproj/project.pbxproj` file metadata/order even
when no intentional project setting changed.

If the project diff is only Xcode noise, discard just that file:

```sh
git restore SequencerAI.xcodeproj/project.pbxproj
```

Intentional project changes should usually be made in `project.yml` and then
regenerated, rather than accepted from incidental Xcode UI edits.
