# Rendered Prototype Screenshots

Generated with headless Chrome from the Mixer Main Out HTML prototypes.

Approved direction: `../mixer-main-out-variant-a.html`

```sh
node scripts/render-html-prototype-screenshots.mjs \
  docs/roadmap/mixer-main-out/prototypes/mixer-main-out-variant-a.html \
  docs/roadmap/mixer-main-out/prototypes/rendered/mixer-main-out-variant-a \
  'idle=setState("idle")' \
  'mid-signal=setState("mid-signal")' \
  'near-clip=setState("near-clip")' \
  'clipped=setState("clipped")' \
  'crossfader-b=setState("xf-b")'
```

Variant B comparison:

```sh
node scripts/render-html-prototype-screenshots.mjs \
  docs/roadmap/mixer-main-out/prototypes/mixer-main-out-variant-b.html \
  docs/roadmap/mixer-main-out/prototypes/rendered/mixer-main-out-variant-b \
  'idle=setState("idle")'
```

Use these images as target evidence for UX/IA reviews:

- `mixer-main-out-variant-a/idle.png`
- `mixer-main-out-variant-a/mid-signal.png`
- `mixer-main-out-variant-a/near-clip.png`
- `mixer-main-out-variant-a/clipped.png`
- `mixer-main-out-variant-a/crossfader-b.png`
- `mixer-main-out-variant-b/idle.png`
