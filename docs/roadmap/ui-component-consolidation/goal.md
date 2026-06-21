# Goal: UI component consolidation (`/simplify everything` follow-up)

Source: `/simplify everything` over the session diff `5e794f9c..HEAD` (2026-06-21),
four parallel cleanup reviews (reuse / simplification / efficiency / altitude).
The dead-code and cheap-compute wins were applied in commit `762b726a` (deleted
`PerformOverviewDashboard.swift`, dead slicer bindings, dead `rangePreview`,
`TransportPhraseProgress` compute-once). What remains is **duplication that needs
a dedicated, pixel-verified refactor** — these were deliberately NOT done in the
cleanup pass because they span heavily-used visual surfaces where an unverified
edit risks silent visual drift (mixer/track/FX surfaces have a history of agents
overselling fixes here).

These are **behaviour-preserving refactors**: the user-visible result must be
**pixel-identical** to today, except where a slice explicitly intends a change.
That is the whole verification bar — see below.

## Process for every slice (verification is mandatory, not optional)

Work in a worktree off `main`. For EACH slice:

1. **Baseline first.** Before touching code, force a fresh build and capture the
   exact QA rows that exercise the surface, into a saved baseline:
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS,arch=arm64' build`
   then `QA_SURFACE_CAPTURE_FILTER=<rows> SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1 bash scripts/visual-scenarios/qa-surface-coverage.sh`
   and copy the resulting PNGs in `.meta/multipass/visual-review/main/` to a
   `baseline/` stash for that slice.
2. **Refactor.** One logical change per commit, standard trailers
   (`Co-Authored-By: Claude Opus 4.8 (1M context) …` / `Claude-Session: …`). New
   file → commit the regenerated `project.pbxproj` reference (it IS tracked).
   Restore `Sources/Resources/Info.plist` from HEAD if xcodegen runs. Do NOT
   touch the uncommitted `SequencerAIApp.swift` / `SequencerAIAppDelegate.swift`
   / `peekaboo-common.sh`.
3. **Build green** (`xcodebuild … build` → BUILD SUCCEEDED). SourceKit
   "cannot find type in scope" whole-file diagnostics after an edit are spurious
   index staleness — trust a green xcodebuild.
4. **After-capture + pixel diff.** Force a fresh build, re-capture the same rows,
   and **compare after-PNGs against the baseline pixel-for-pixel**. For a pure
   refactor the requirement is **zero visual drift**. Any difference must be
   either intended-and-documented or fixed before the slice lands.
5. **Independent verification.** A SEPARATE agent (not the implementer) reads the
   baseline and after PNGs and confirms parity — verify pixels, not the
   implementer's report. Non-visual slices (W5 audio, W7 infra) instead require
   the full test suite green + a manual smoke note.
6. **No silent scope creep.** If a slice can't reach parity, stop and report
   rather than shipping a visual regression.

A slice is DONE only when: build green + after-PNGs match baseline (or documented
intended diff) + independent verifier signed off + tests green where applicable.

---

## W1 — Shared FX insert chain (HIGH — biggest win)

The insert-chain UI is implemented THREE times, near-verbatim:
- `Sources/UI/TrackSource/TrackFXChainView.swift` (per-track FX)
- `Sources/UI/DrumGroup/KitBusFXChainView.swift` (kit-bus FX)
- `Sources/UI/Mixer/ScenesWorkspaceView.swift` (`insertRow` + `insertEditor`,
  scene/master-bus FX)

Two duplicated pieces: (a) the **insert row** (drag handle + accent icon well +
name/subtitle + bypass switch + ✕, `subtleFill` tile w/ selection stroke); and
(b) the **native-insert parameter editor** (filter radial knobs + `SceneFilterCurveView`
+ segmented mode control; bitcrusher sliders). The kit view's header comment
already admits it "Mirrors the Scenes FX grammar". `TrackFXChainView.iconName(for:)`
is even cross-referenced from the kit view — they already belong together.

**Do:** extract `InsertChainRow` and `NativeInsertParameterEditor(kind:accent:onChange:)`
(value-in / closure-out) into a shared location (e.g. `Sources/UI/Theme/` or a new
`Sources/UI/FX/`). Each of the three call sites supplies its own bindings
(`MasterBusInsert` / `MixerBusInsert` / track insert) + mutation closures
(`updateMixerBusInsert` etc.). Keep `SceneFilterCurveView` shared as-is.

**Capture rows:** track FX tab (`trackSourceTab=fx`), `29a-drum-kit-fx-tab`,
`29d-drum-kit-fx-chooser`, the scenes FX editor rows. Plus a populated-chain state
for each (add an insert in the fixture so the row + editor render).

**Acceptance:** all three FX surfaces pixel-identical to baseline in empty AND
populated states; ~350–500 LOC removed; build green; verifier sign-off.

## W2 — Shared segmented control / tab button (HIGH)

Bespoke segmented/pill controls reimplement the same grammar in ≥5 places:
- `DrumKitMatrixView.kitTabButton` (≈ `TrackSourceSlotWellTabBar.slotButton`)
- `DrumGroupRoutingEditor.modeButton` + its container
- `DrumKitMatrixView+Accordion` (`expandedRowTabButton`, `sourceModeButton`)
- `DrumKitMatrixView+Capture` (`historyLengthButton`)
- `TrackWorkspaceView` already defines a private generic `StudioSegmentedControl`
  / `StudioSegment` (1336–1404) — no shared equivalent exists yet.

**Do:** promote `StudioSegmentedControl` (and a `StudioSlotTabButton` for the
underline-tab grammar) to `Sources/UI/Theme/`, then route the kit tab bar,
routing-editor mode buttons, accordion chips, and capture length buttons through
it. The kit tabs are label-only (no per-tab accent/badge) — generalize minimally.

**Capture rows:** `29`, `29a`, `29b`, `29c` (kit tabs), `31-drum-kit-routing`,
`29g` (accordion), `29e`/`29f` (capture). Also re-verify the normal-track tab bar
(`22b` etc.) since `TrackSourceSlotWellTabBar` may be touched.

**Acceptance:** every listed surface pixel-identical; the track tab bar
unaffected; build green; verifier sign-off.

## W3 — Finish `StudioFXOptionRow` adoption (MED)

`StudioFXOptionRow` (`Sources/UI/Theme/StudioCards.swift`) is used by
`MixerBusStrip` and `MasterOutputColumnView`, but two add-FX sheets still
hand-roll the identical icon+label tile:
- `ScenesWorkspaceView.addInsertOptionButton`
- `DrumKitMatrixView+KitTabs.kitFXOptionButton`

**Do:** route both through `StudioFXOptionRow`.

**Capture rows:** `29d-drum-kit-fx-chooser`, the scenes add-FX sheet.
**Acceptance:** both sheets pixel-identical; build green; verifier sign-off.

## W4 — `StepLayerRotaryDial` → wrap `StudioRotaryKnob` (MED)

`Sources/UI/Slicer/SliceTrackEditingControls.swift` `StepLayerRotaryDial`
reimplements the arc+vertical-drag rotary that `StudioRotaryKnob` provides; only
the selected-layer outline + tap-to-select are extra. Wrap `StudioRotaryKnob`
and keep the selection chrome around it.

**Capture rows:** the slicer step-grid layer controls (slice editing surfaces).
**Acceptance:** rotary pixel-identical incl. selected state + drag behaviour
(manual drag smoke); build green; verifier sign-off.

## W5 — Single `insertKindShape` helper across Audio hosts (MED — non-visual, audio-correctness-sensitive)

`insertKindShape(for:MasterBusInsertKind)` is byte-identical in
`TrackInsertChainHost`, `MixerBusHost` (×2), `MasterBusHost`; the `graphShape`
diff-detection wrappers are the same logic over different containers.

**Do:** extract one shared `InsertKindShape.make(for:)` in `Sources/Audio/`; have
all four hosts call it. This is audio-graph code — **no behaviour change**, no
work added to the render callback.

**Verification (non-visual):** full unit-test suite green; a manual audio smoke
note (load a kit + a track with inserts, confirm FX still audibly apply). NO
allocation/lock added on the render path.

## W6 — Drum-kit matrix render efficiency (MED — behaviour-preserving)

- `DrumKitMatrixView.accent` rebuilds the entire `DrumKitMatrixModel` (allocates
  `tracksByID`, decodes every member clip grid) just to read `colorHex`, and is
  referenced ~37× per render. Derive the accent from the group color in
  `session.store.trackGroups` without building the model, or build `model` once
  in `body` and thread it.
- `DrumKitMatrixView+Capture` calls `engineController.captureSnapshot(trackID:)`
  3–4× per part per render (each takes a lock + copies the rolling buffer).
  Snapshot each member ONCE per render and pass it down.
- `longestRowLength(model)` is recomputed 3–4× per render (header + matrix);
  compute once and pass the value.

**Capture rows:** `29`, `29e`, `29f`, `29g` (kit matrix + capture).
**Acceptance:** pixel-identical output (this is a perf-only change); build green;
verifier sign-off. Optional: a before/after note on snapshot/lock call count.

## W7 — Decide the fate of drum-group pattern-linking infra (DECISION + execute)

`setDrumGroupPatternLinked` / `reLinkDrumGroupPattern` (session + `Project+Destinations`),
`TrackGroup.isPatternLinked`, and `DrumKitMatrixModel.needsReLink` survive, but
the UI affordance was removed this session ("Re-link controls are gone"). The
only remaining drivers are `DrumKitMatrixView+VisualCommand` and
`DrumKitMatrixEditingTests`. NOTE: `isPatternLinked` defaults `true` and still
affects kit-collapse behaviour in `TracksMatrixView`/`LiveWorkspaceView`, so it
is NOT purely dead.

**This is a product decision — confirm with the owner before executing:**
(a) keep linking as a real feature (restore an affordance), or (b) retire the
mutation surface + `needsReLink` + the visual commands + their tests, keeping
only whatever `isPatternLinked` semantics the collapse behaviour genuinely needs.

**Acceptance:** either an affordance exists, or the orphaned mutation/command/
test surface is gone and the retained `isPatternLinked` use is documented; tests
green; collapse behaviour unchanged (capture `02-tracks-navigator` parity).

## W8 — Split `TrackRoutingTabContent` Mode enum into two views (LOW)

The `enum Mode { sound, mixer }` multiplexes one struct into two layouts that
share nothing. Split into `TrackSoundTabContent` + `TrackMixerTabContent`.
Low value; do only if W1–W7 land cleanly. **Caution:** this surface was just
unified this session — capture `19`/`22b`/`27b`/`29c` and require parity.

## W9 — Generic status dictionary in VisualScenarioCommandRunner (LOW — risky)

The runner accretes a `private static var …Rendered*` mirror + an observer line +
a status line per QA surface. A `[String:String]` keyed by surface would collapse
the triplicated boilerplate. **High risk:** the status string is parsed by the
capture status-waits — any format change can break the whole harness. Do LAST,
and verify by running the FULL capture sweep (all rows) green, not a subset.

---

## Suggested order

W1 → W2 → W3 → W4 (the shared-component wins, each independently verifiable) →
W6 (perf) → W5 (audio, separate verification track) → W7 (needs owner decision)
→ W8/W9 (optional, only if everything above is clean).

Track progress in this file (check off slices as their verifier signs off).
Do not mark a slice done on an implementer's report alone — pixel parity or test
green is the gate.
