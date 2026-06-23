# Diagrams

This directory keeps architecture diagrams as source-controlled text first and
SVG artifacts second.

## Source Of Truth

Editable sources live in `docs/diagrams/src/*.d2`. The checked-in SVG files in
`docs/diagrams/*.svg` are review artifacts for the wiki and GitHub browsing.
Do not hand-edit SVGs unless `d2` is unavailable and the change is explicitly
called out in review.

D2 is the default for canonical system maps because it is diffable and scales
better than inline Mermaid for ownership bands, legends, and labeled runtime
boundaries. Mermaid is still fine for small wiki sketches that explain one local
idea and do not need generated artifacts.

## Render

Install D2 locally, then render all canonical diagrams:

```bash
scripts/diagrams/render-d2.sh
```

The script intentionally does not install tools. On macOS, one local option is:

```bash
brew install d2
```

## Check

To verify SVG artifacts match the D2 sources:

```bash
scripts/diagrams/check-d2-rendered.sh
```

When `d2` is not installed this check is advisory and exits successfully. Set
`REQUIRE_D2=1` to make missing D2 fail, which is useful once CI standardizes the
toolchain.

## Runtime Ownership

The runtime ownership diagrams use labels from
`docs/architecture/runtime-ownership-manifest.yml`:

- `lifetime`: persisted, session, compiled-snapshot, runtime, cache, diagnostic
- `owner`: document, live-store, session, engine, audio, UI, app
- `thread`: main, tick-clock, audio-engine-main, render/tap-callback, background
- `realtime_class`: safe-hot-read, realtime-adjacent, main-only,
  structural-edit, forbidden-hot-path

Run the first mechanical guard with:

```bash
scripts/diagnostics/runtime-ownership-lint.sh
```
