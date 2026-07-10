# Marketing Website Publishing

## Purpose

The public In Sequence marketing website lives in the neighboring
`../inseq-website` checkout. It presents two artifacts owned by this project:

- the latest broad UI capture set, used by the website gallery;
- the latest notarized Developer ID DMG, used by the download link.

The website is a Cloudflare Worker with static assets. Its worker reads the
capture gallery from the `ux-captures` R2 bucket and releases from the
`in-seq-builds` R2 bucket.

## Discover The Published Build

Agents should query the durable website marker instead of guessing from local
DerivedData or package directories:

```sh
scripts/latest-build.sh
scripts/latest-build.sh --json
scripts/latest-build.sh --download-url
```

The website endpoints are:

- `/api/releases/latest` for machine-readable release metadata;
- `/download/latest` for the current DMG;
- `/api/gallery` for the published capture gallery.

The release metadata includes the filename, R2 key, build commit and branch,
publication time, byte size, content type, and SHA-256 digest.

## Publish Captures

First record and absorb the project capture set using the standard workflow in
`AGENTS.md`. Then publish the latest sufficiently broad absorbed run:

```sh
scripts/update-website-assets.sh --captures --dry-run
scripts/update-website-assets.sh --captures
```

The wrapper delegates to `../inseq-website` and runs its `gallery:update`
publisher. By default, focused one-row runs cannot replace the public gallery.
Use `--run-id` for an explicit run or `--min-rows` only when deliberately
changing the minimum breadth.

## Publish A Download

The wrapper does not build or notarize. Create a fresh package from a clean
checkout or worktree first:

```sh
scripts/package-developer-id.sh \
  --team-id TEAM_ID \
  --notary-profile seqai-notary
```

After notarization, stapling, Gatekeeper verification, and checksum validation
pass, publish the resulting DMG:

```sh
scripts/update-website-assets.sh --download \
  --dmg /absolute/path/InSequence-COMMIT-developer-id.dmg \
  --dry-run

scripts/update-website-assets.sh --download \
  --dmg /absolute/path/InSequence-COMMIT-developer-id.dmg
```

The standard filename lets the wrapper infer the binary commit. Pass
`--build-commit SHA` when using a nonstandard filename. The upload writes the
DMG under `in-seq-builds/releases/developer-id/` and updates
`releases/developer-id/latest.json`.

## Publish Both

```sh
scripts/update-website-assets.sh --all \
  --dmg /absolute/path/InSequence-COMMIT-developer-id.dmg
```

This is the normal command when the product owner asks to update the marketing
site with both the latest UI and latest downloadable build.

## Verification

After publication:

1. Run `scripts/latest-build.sh` and confirm the binary commit and SHA-256.
2. Fetch `/api/gallery` and confirm the intended capture run is first.
3. Check `/download/latest` returns the expected DMG headers.
4. Do not overwrite unrelated dirty source changes in `../inseq-website`; the
   gallery publisher writes R2 objects and does not require cleaning that repo.

Developer ID creation and notarization details remain in
[`developer-id-distribution.md`](developer-id-distribution.md).
