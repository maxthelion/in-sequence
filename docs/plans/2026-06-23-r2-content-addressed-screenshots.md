# Plan: Content-Addressed Screenshot Store on Cloudflare R2

**Status:** Proposed — revisit 2026-06-24
**Author:** Max + Claude
**Context:** QA visual-capture harness (`scripts/visual-scenarios/qa-surface-coverage.sh`
+ `peekaboo-common.sh`) currently writes PNGs into the working tree under
`.meta/multipass/visual-review/<branch-slug>/`. These are large, churn on every
capture, and bloat the repo if committed. We want durable history of every
surface render without storing duplicate bytes.

## Goal

Keep **one stored blob per unique image** (keyed by content hash) and a
**per-commit manifest** mapping each scenario row to the hash it rendered. When
a surface doesn't change between commits, its row points at the same blob — zero
new bytes. When it does change, a new blob is uploaded and the new commit's
manifest points at it. Full history is reconstructable from the manifests; bytes
are stored exactly once.

This is git's own object model (content-addressed blobs + per-tree pointers)
applied to screenshots, with the blob store living in R2 instead of the repo.

## Why R2

- Off-repo: the working tree and git history stay free of binary churn.
- S3-compatible API → standard tooling (`aws s3`, `rclone`, or the R2 SDK).
- No egress fees → cheap to pull historical captures for diffing/review.
- Immutable, content-addressed keys → safe to cache forever, no invalidation.

## Data model

### Blob store (R2 bucket, content-addressed)

```
screenshots/<md5>.png          # the image bytes, keyed by their own hash
```

- Key = hash of the PNG bytes (md5 is sufficient — this is dedupe, not
  security; sha256 is fine too and avoids any collision worry, decide at impl).
- A blob is written **once**; re-uploading the same hash is a no-op (check
  `HEAD` first, skip if present).
- Never deleted by the normal flow → this is the history.

### Manifest (per commit)

One JSON manifest per captured commit, stored both in R2 and (small enough to)
committed in-repo for offline lookup:

```
manifests/<commit-sha>.json
```

```jsonc
{
  "commit": "03ca795f...",
  "branch": "bug-batch-20260623",
  "capturedAt": "2026-06-23T18:48:00Z",
  "rows": {
    "01-phrase":                 { "md5": "a1b2…", "status": "captured" },
    "02-tracks-navigator":       { "md5": "c3d4…", "status": "captured" },
    "29-drum-kit-matrix":        { "md5": "a1b2…", "status": "captured" }
    // note: 01-phrase and 29-… can share a hash only if pixel-identical;
    // normally each row has its own hash, but unchanged rows across commits
    // reuse the prior commit's hash → that's where the dedupe pays off.
  }
}
```

Dedupe wins across **commits**, not across rows within a commit: row N in
commit A and row N in commit B share a blob whenever that surface didn't change.

## Workflow

### Capture → upload (after a harness run)

1. Run the harness as today → PNGs land in
   `.meta/multipass/visual-review/<branch-slug>/`.
2. For each `<row>.png`:
   - compute `hash = md5(bytes)`
   - `HEAD screenshots/<hash>.png` on R2 → if missing, `PUT` it
   - record `rows[row] = { md5: hash, status }`
3. Write `manifests/<commit-sha>.json` to R2 and to the repo
   (`.meta/multipass/visual-review/manifests/<sha>.json` — tiny, safe to
   commit).
4. Working-tree PNGs become disposable (regenerable from R2 by hash).

A new script `scripts/visual-scenarios/r2-sync.sh` owns steps 2–3. Keep it
**separate** from the capture script so capture stays usable offline.

### Review / diff (pull a historical render)

- `r2-fetch.sh <commit-sha> [row]` reads the manifest, resolves the hash(es),
  pulls `screenshots/<hash>.png` into a local cache (`~/.cache/seq-shots/` or
  `.meta/.../_cache/`).
- Diff two commits for a row = resolve both hashes; if equal → "no visual
  change" without downloading; if different → fetch both and image-diff.

## `.gitignore` / repo hygiene

- Keep ignoring the PNGs under `.meta/multipass/visual-review/<slug>/`.
- **Do** commit `manifests/*.json` (kilobytes) so history/diffing works from a
  clean checkout without R2 credentials.

## Config & secrets

- Bucket name + account id + S3 endpoint in a non-secret config
  (`scripts/visual-scenarios/r2.env.example`).
- Credentials via env (`R2_ACCESS_KEY_ID` / `R2_SECRET_ACCESS_KEY`) — never
  committed. Read from the keychain or a gitignored `r2.env`.
- Guard: `r2-sync.sh` no-ops with a clear message if creds are absent, so the
  harness never hard-fails on a machine without R2 access.

## Open questions (resolve on revisit)

1. **Hash function** — md5 (shorter keys, fine for dedupe) vs sha256 (no
   collision worry). Lean md5 unless we want the blobs to double as integrity
   proofs.
2. **Tooling** — `aws s3` CLI (already common) vs `rclone` vs R2 SDK. `aws s3`
   against the R2 S3 endpoint is the least new surface.
3. **Manifest in-repo vs R2-only** — committing them adds tiny diffs per
   capture run; the upside is offline diffing. Probably commit them but only on
   "blessed" capture runs, not every loop iteration, to avoid noise.
4. **Retention** — blobs are never deleted by default; do we ever GC
   unreferenced hashes? Probably not (cheap), but a `r2-gc.sh` that keeps only
   hashes referenced by the last N manifests is an easy add later.
5. **Branch namespacing** — manifests are keyed by commit sha (branch-agnostic),
   which is better than today's branch-slug dirs; record branch as metadata
   only.

## Rough effort

- `r2-sync.sh` (hash, HEAD-check, PUT, write manifest): ~half a day.
- `r2-fetch.sh` + diff helper: ~half a day.
- Wire an opt-in hook at the end of `qa-surface-coverage.sh` (only when
  `R2_*` creds present): ~1 hour.

Total: ~1–1.5 days, incremental and non-blocking — the existing local capture
flow keeps working untouched if R2 is never configured.
