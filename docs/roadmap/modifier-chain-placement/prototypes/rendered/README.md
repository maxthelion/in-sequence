# Rendered Prototype Screenshots

Generated from `../modifier-chain-placement-slot-well.html` with headless
Chrome:

```sh
node scripts/render-html-prototype-screenshots.mjs \
  docs/roadmap/modifier-chain-placement/prototypes/modifier-chain-placement-slot-well.html \
  docs/roadmap/modifier-chain-placement/prototypes/rendered \
  'source-clip=setState("clip-occupied")' \
  'source-generator=setState("gen-occupied")' \
  'source-empty=setState("empty-slot")' \
  'source-picker=setState("picker-open")' \
  'after-swap=setState("swap-done")' \
  'modifier-empty=setState("modifier-empty")' \
  'modifier-occupied=setState("gen-occupied"); switchTab("modifier")'
```

Use these images as the target evidence for UX/IA reviews:

- `source-clip.png`
- `source-generator.png`
- `source-empty.png`
- `source-picker.png`
- `after-swap.png`
- `modifier-empty.png`
- `modifier-occupied.png`
