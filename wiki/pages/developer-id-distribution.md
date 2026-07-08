# Developer ID Distribution

In Sequence can be packaged for distribution to other Macs from the command
line. The normal path is `scripts/package-developer-id.sh`; opening Xcode is not
required, and the script does not intentionally edit `project.yml` or
`SequencerAI.xcodeproj/project.pbxproj`.

## One-Time Setup

Install the Developer ID Application certificate in the login keychain.

Store App Store Connect notarization credentials in the keychain:

```sh
xcrun notarytool store-credentials seqai-notary \
  --apple-id YOUR_APPLE_ID \
  --team-id TEAMID \
  --password APP_SPECIFIC_PASSWORD
```

`TEAMID` is the Apple Developer team identifier associated with the Developer ID
certificate. The password must be an Apple app-specific password, not the Apple
ID account password. Apple generates app-specific passwords from the Apple ID
account page.

## Clean Worktree Packaging

Package from a clean checkout, or from a temporary clean worktree pinned to the
commit being distributed:

```sh
git worktree add --detach /tmp/in-sequence-package-$(git rev-parse --short HEAD) HEAD
cd /tmp/in-sequence-package-$(git rev-parse --short HEAD)

scripts/package-developer-id.sh \
  --team-id TEAMID \
  --identity "Developer ID Application: Your Name (TEAMID)" \
  --notary-profile seqai-notary \
  --output-dir /Users/maxwilliams/dev/in-sequence-distribution/$(git rev-parse --short HEAD)-in-sequence-notarized
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
9. Produces the final distributable DMG.

The Xcode target/scheme and bundle identifier remain `SequencerAI` /
`ai.sequencer.SequencerAI`; the user-facing app/document names and distributed
bundle filename are `In Sequence`.

## R2 Upload

For release uploads, use a dedicated distribution bucket/key rather than the
visual QA screenshot bucket. The script reads a gitignored
`scripts/distribution.r2.env`, `$R2_ENV_FILE`, `.env`, or the live shell
environment:

```sh
R2_DISTRIBUTION_BUCKET=in-sequence-releases
R2_DISTRIBUTION_ENDPOINT=https://ACCOUNT_ID.r2.cloudflarestorage.com
R2_DISTRIBUTION_ACCESS_KEY_ID=...
R2_DISTRIBUTION_SECRET_ACCESS_KEY=...
R2_REGION=auto
R2_DISTRIBUTION_PREFIX=releases/developer-id
```

Then package and upload the final DMG:

```sh
scripts/package-developer-id.sh \
  --team-id TEAMID \
  --identity "Developer ID Application: Your Name (TEAMID)" \
  --notary-profile seqai-notary \
  --upload-r2
```

Use `--r2-key <key>` when the release object path should be exact rather than
`$R2_DISTRIBUTION_PREFIX/<dmg-name>`.

## Verification

After packaging, verify the exported app and final DMG before sharing:

```sh
codesign --verify --deep --strict --verbose=2 "/path/to/export/In Sequence.app"
xcrun stapler validate "/path/to/export/In Sequence.app"
spctl --assess --type execute --verbose=4 "/path/to/export/In Sequence.app"
codesign --verify --verbose=2 "/path/to/InSequence-COMMIT-developer-id.dmg"
xcrun stapler validate "/path/to/InSequence-COMMIT-developer-id.dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "/path/to/InSequence-COMMIT-developer-id.dmg"
```

The expected `spctl` result is `accepted` with `source=Notarized Developer ID`.

## Useful Options

Create a signed but unnotarized artifact for local smoke testing:

```sh
scripts/package-developer-id.sh \
  --team-id TEAMID \
  --identity "Developer ID Application: Your Name (TEAMID)" \
  --skip-notarize
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
