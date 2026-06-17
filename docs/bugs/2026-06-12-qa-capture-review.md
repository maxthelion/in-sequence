# QA capture review — 2026-06-12 (lens 1, set main-21b2b9c2)

Observer pass over the 44-surface set against docs/ux-canon.md
(rules 1-12). The flat grammar, mixer scaffold, 4-up rotaries, step
grid gaps, and library page all hold up. Four findings, none P0:

## F1 — Tracks edit cards reserve height they don't use (rule echo of
the owner's wasted-space rulings)
`02-tracks-edit`: each card's content (icon row + 4x4 swatch grid)
ends ~40% down the card; the lower 60% is empty fill, and the page
below the single row is bare ground. The card height (210pt, matched
to perform mode) makes edit mode look hollow. Options: let edit-mode
cards size to content, or surface useful info (destination, source
mode) in the reserved space. Needs an owner taste call between them.

## F2 — Build pill leaks raw "unknown unknown" (rule 3: no raw
IDs/placeholders in chrome)
Top bar reads "main 21b2b9c2 unknown unknown" — gitDirty and
attribution fields render their fallback strings to every screenshot.
BuildIdentity.compactDisplay should omit unknown fields instead of
printing them.

## F3 — Library zero-count categories read at full strength
`40-library-global`: 0-count categories (Pedal Hat, Low/Mid/High Tom,
Crash, Cowbell...) render identically to populated ones. Dim them (or
collapse under "empty categories") so the eye lands on real content
(rule 11).

## F4 — Crossfader value not in accent (rule 12.3 nit)
`06-scenes-perform`: the A/B blend "0%" renders in plain text; values
elsewhere (BPM, dB readouts) are accent-colored. One-line token fix.

Non-findings verified good: phrase matrix solid blocks; slicer empty
state via Add Loop card (progressive disclosure); scenes macro knobs
solid-when-set/dashed-when-empty; mixer scaffold row alignment; sends
grouped at master; no clipping or text deformation anywhere in the set.

Suggested disposition: F2+F4 are one small sweep slice; F3 small; F1
needs Max's pick first.

## Resolution (2026-06-12, feature/capture-review-sweep)

F2–F4 fixed in one sweep; landed on main at 23619634 (foreman
fast-forward after gate).

- **F2 fixed** (b6c21d6f): `BuildIdentity.compactDisplay`
  (Sources/App/SequencerAIAppDelegate.swift) now omits fields whose
  value is "unknown"; all-unknown collapses to a single "unknown".
  `logSummary` still reports every field for diagnostics. New test
  pins the unknowns-omitted behaviour
  (SequencerAIAppDelegateTests.test_buildIdentity_compactDisplayOmitsUnknownFields).
- **F3 fixed** (ddf82bee): Library zero-count category rows
  (Sources/UI/Library/LibraryWorkspaceView.swift, categoryRow) dim to
  `mutedText.opacity(StudioOpacity.inheritedContent)` for label and
  count; rows stay selectable.
- **F4 fixed** (23619634): Scenes perform A/B blend percent
  (Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift,
  crossfaderBridge) renders in the panel's amber accent per rule
  12.3, matching the BPM readout pattern.

Gate: full suite TEST SUCCEEDED — 1427 executed, 19 skipped
(standard two-test skip list), 0 failures.

**F1 remains open** — tracks-edit card height needs Max's taste call
(size-to-content vs surface destination/source info in the reserved
space).
