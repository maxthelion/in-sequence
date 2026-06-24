# Verify: in-kit macro sheet

**Ref:** bug 131730 (2026-06-23 batch, on `main`).
**Decision applied:** "If macros are on single view but not kit view, add them to
kit view." Fix committed; needs **GUI** confirmation.

## Why a human
Macros surface inside the drum-kit view as a sheet/tab; verifying it renders and
binds correctly is a visual + interaction check.

## How to verify
1. Open a drum-group track → kit view → macros tab/sheet.
2. PASS = macros are present in the kit view (parity with the single-track
   view), and binding/editing a macro works.
