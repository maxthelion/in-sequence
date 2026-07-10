# Website Asset Publishing

Use `scripts/update-website-assets.sh` from this repo when an agent needs to refresh the public In-Sequence website assets.

## Captures

Captures must already be absorbed by Bug Reporter. The script reads the latest absorbed `in-sequence` run through the website repo's gallery publisher, then updates the website R2 manifest/index in `ux-captures`.

```sh
scripts/update-website-assets.sh --captures
```

Useful variants:

```sh
scripts/update-website-assets.sh --captures --dry-run
scripts/update-website-assets.sh --captures --run-id RUN_ID
scripts/update-website-assets.sh --captures --min-rows 1
```

By default the website publisher chooses the newest run with enough rows for a real gallery, so small focused bugfix capture runs do not replace the public gallery unless `--min-rows 1` or `--run-id` is used.

## Latest Download

To update the website download pointer, upload an existing DMG:

```sh
scripts/update-website-assets.sh --download --dmg dist/developer-id/InSequence-...dmg
```

If `--dmg` is omitted, the newest `dist/developer-id/*.dmg` is used.

This delegates to `scripts/r2-upload-artifact.mjs`, uploading to:

- bucket: `in-seq-builds`
- release prefix: `releases/developer-id`
- latest pointer: `releases/developer-id/latest.json`

To create a fresh notarized DMG first, run `scripts/package-developer-id.sh` with the appropriate Developer ID and notary options. That packaging step is intentionally separate from the website update wrapper.

## Both

```sh
scripts/update-website-assets.sh --all --dmg dist/developer-id/InSequence-...dmg
```

Use `--dry-run` to verify both sides without writing to R2.
