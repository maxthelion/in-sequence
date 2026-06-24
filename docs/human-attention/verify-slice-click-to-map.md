# Verify: slicer click-to-map

**Ref:** bug 131354 (2026-06-23 batch, on `main`).
**Status:** fix committed; needs **GUI** confirmation.

## Why a human
Click-to-map is a pointer interaction on the slicer surface — needs a real
window + click, not capturable headlessly with confidence.

## How to verify
1. Open a slicer track → slice tab with a populated sample.
2. Click a slice to map/assign it to a step (the click-to-map gesture).
3. PASS = the click maps the slice as expected; the mapping is reflected in the
   grid and plays back the intended slice.
