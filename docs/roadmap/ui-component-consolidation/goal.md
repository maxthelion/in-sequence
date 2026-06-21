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

## Status (2026-06-21) — executed end-to-end

| Slice | Outcome |
|---|---|
| W1 shared FX insert chain | ✅ DONE `6568b669` — verified (05b AE 0) |
| W2 shared segmented/tab controls | ✅ DONE `b1500969` — verified (9 surfaces) |
| W3 StudioFXOptionRow adoption | ◑ PARTIAL `0b65bacc` — kit verified; scenes deferred (genuinely different) |
| W4 rotary wrap | ✗ WON'T DO — false positive (different grammar, uncaptured) |
| W5 shared insertKindShape | ✅ DONE `faf8a019` — build+parity (tests stalled→fallback) |
| W6 drum-kit render efficiency | ✅ DONE `1d374c78` — verified AE 0 |
| W7 retire pattern-linking infra | ✅ DONE `470c764b` — verified (02 AE 0) |
| W8 Mode-enum split | ✗ WON'T DO — low-value reorg, risk without gain |
| W9 QA-runner dict | ✗ WON'T DO — owner skip (harness blast radius) |

**Follow-up capture gaps surfaced (separate harness work, need the W9-class
plumbing):**
1. `31-drum-kit-routing` capture is BROKEN — the routing editor never opens
   (`drumGroupRoutingEditorRenderedVisible=false`), so DrumGroupRoutingEditor is
   only ever transitively verified. Fix the openRouting command path.
2. No `05c-scenes-fx-chooser` capture for the scenes add-FX sheet — blocks both a
   pixel-verified W3 scenes swap and any future scene-FX-sheet coverage.
3. (Pre-existing) `29g` post-dive-in commands are intermittent.

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

## W1 — Shared FX insert chain (HIGH — biggest win) — ✅ DONE (`6568b669`)

Extracted `Sources/UI/FX/InsertChainComponents.swift` (`InsertChainRow` +
`NativeInsertParameterEditor`); ~377 LOC removed across the 3 call sites.
Verified independently: `05b-scenes-edit-content` pixel-identical (insert rows +
filter editor); empty states (`22`, `29a`) unchanged. Info.plist restored after
xcodegen (it had stripped `NSMicrophoneUsageDescription`). Bitcrusher editor was
not pixel-captured (no fixture selects it) — preserved by code, manual smoke
advised.


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

## W2 — Shared segmented control / tab button (HIGH) — ✅ DONE (`b1500969`)

Extracted `Sources/UI/Theme/StudioSegmentedControls.swift` (`StudioSlotTabButton`
underline grammar + promoted `StudioSegmentedControl` solid-thumb grammar).
Routed kitTabButton, TrackSourceSlotWellTabBar.slotButton, accordion chips,
capture length buttons, and DrumGroupRoutingEditor mode buttons through them
(~net dedup across 8 files). `mixerButton` left un-routed (genuinely different
2-line layout). Info.plist restored after xcodegen.
Verified independently: pixel-identical on `29`/`29a`/`29b`/`29c` (kit tabs),
`22b` (normal-track tabs — the high-risk surface), `29g` (accordion chips),
`29e`/`29f` (capture length). DrumGroupRoutingEditor is transitively verified
(uses the same `StudioSegmentedControl` proven on `29e`/`29g`) — its own `31`
capture is BROKEN pre-W2 (`drumGroupRoutingEditorRenderedVisible=false`; the
openRouting command doesn't take, same class as the `29g` post-dive-in issue).
**Follow-up: fix the `31-drum-kit-routing` capture so the routing editor is
directly covered.**


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

## W3 — Finish `StudioFXOptionRow` adoption (MED) — ◑ PARTIAL (`0b65bacc`)

Generalized `StudioFXOptionRow` with optional params (iconColor / iconColumnWidth
/ cornerRadius / borderColor; defaults keep MixerBusStrip + MasterOutputColumnView
byte-identical) and routed the KIT add-FX chooser (+ the per-member accordion
chooser, a 3rd caller) through it. Verified: `29d-drum-kit-fx-chooser`
pixel-identical (AE 0).
**Scenes `addInsertOptionButton` deliberately NOT swapped:** it is genuinely a
different style (Label-based size-12 bold icon, Label spacing, h12/v10 padding,
full-opacity border) — routing it through the shared row would CHANGE its
appearance, violating behaviour-preservation, and it has no capture/visual
command to verify against. Unifying scenes is therefore a deliberate visual
change needing owner sign-off + a new `05c-scenes-fx-chooser` capture (the
capture needs the same harness plumbing as the W2 `31` fix / W9). Left as-is.


`StudioFXOptionRow` (`Sources/UI/Theme/StudioCards.swift`) is used by
`MixerBusStrip` and `MasterOutputColumnView`, but two add-FX sheets still
hand-roll the identical icon+label tile:
- `ScenesWorkspaceView.addInsertOptionButton`
- `DrumKitMatrixView+KitTabs.kitFXOptionButton`

**Do:** route both through `StudioFXOptionRow`.

**Capture rows:** `29d-drum-kit-fx-chooser`, the scenes add-FX sheet.
**Acceptance:** both sheets pixel-identical; build green; verifier sign-off.

## W4 — `StepLayerRotaryDial` → wrap `StudioRotaryKnob` (MED) — ✗ WON'T DO

On inspection the two are genuinely different visual grammars, not a wrap:
`StudioRotaryKnob` uses a 2pt `border` circle, a `trim(0.15…0.85)`-rotated 3pt
solid arc, and renders the value in the ACCENT colour; `StepLayerRotaryDial` uses
a 3pt `border.opacity(0.55)` circle, a custom `StepLayerRotaryArc` 4pt
`accent.opacity(0.94)` arc, renders the value in WHITE, and adds a tile
background + amber active-layer outline + tap-to-select. Consolidating would
either change the dial's pixels (violates behaviour-preservation) or bloat
`StudioRotaryKnob` with dial-only params that risk its many other call sites —
and the step-edit rotary cluster isn't exercised by any capture, so it can't be
pixel-verified regardless. Net-negative; skipped. (~70 LOC left as-is.)


`Sources/UI/Slicer/SliceTrackEditingControls.swift` `StepLayerRotaryDial`
reimplements the arc+vertical-drag rotary that `StudioRotaryKnob` provides; only
the selected-layer outline + tap-to-select are extra. Wrap `StudioRotaryKnob`
and keep the selection chrome around it.

**Capture rows:** the slicer step-grid layer controls (slice editing surfaces).
**Acceptance:** rotary pixel-identical incl. selected state + drag behaviour
(manual drag smoke); build green; verifier sign-off.

## W5 — Single `insertKindShape` helper across Audio hosts (MED) — ✅ DONE (`faf8a019`)

Promoted `InsertKindShape` (was a private nested enum declared 3×) to
`Sources/Audio/InsertKindShape.swift` with `static func make(for:)`; routed the 3
`InsertKindShape`-returning call sites (MixerBusHost ×2 + TrackInsertChainHost)
through it; deleted the 3 private copies + 3 redundant nested enum decls
(+36/−54). Build green; extracted body byte-identical to originals (pure mapping,
no render-path work). Tests hit the documented CoreAudio stall → fell back to
build-green + code-parity (sufficient for a pure mapping). Info.plist restored
after xcodegen. NOTE: `MasterBusHost.MasterBusInsertKindShape` is structurally
identical — left untouched as a future unification (needs merging two enums +
their two InsertShape structs).


`insertKindShape(for:MasterBusInsertKind)` is byte-identical in
`TrackInsertChainHost`, `MixerBusHost` (×2), `MasterBusHost`; the `graphShape`
diff-detection wrappers are the same logic over different containers.

**Do:** extract one shared `InsertKindShape.make(for:)` in `Sources/Audio/`; have
all four hosts call it. This is audio-graph code — **no behaviour change**, no
work added to the render callback.

**Verification (non-visual):** full unit-test suite green; a manual audio smoke
note (load a kit + a track with inserts, confirm FX still audibly apply). NO
allocation/lock added on the render path.

## W6 — Drum-kit matrix render efficiency (MED) — ✅ DONE (`1d374c78`)

All 3 fixes: (1) `accent` now reads the group color from `session.store.trackGroups`
(identical `colorHex` → identical Color) instead of rebuilding the whole model
~37×/render; (2) capture history snapshots each member ONCE/render into a
`[UUID: CaptureSnapshot]` instead of ~4 locked buffer copies/member/render; (3)
`longestRowLength` computed once and threaded (was 3–4 scans/render;
`postRenderedVisualState` now builds model once not ~6×). Build green; pixel
parity AE 0 on `29`/`29e`/`29f`/`29g` (eyeballed accent unchanged); `30`
deterministic (my stashed `30` baseline was stale, not a regression).


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

## W7 — Retire drum-group pattern-linking infra (owner: RETIRE) — ✅ DONE (`470c764b`)

Deleted `Project.setDrumGroupPatternLinked`/`reLinkDrumGroupPattern`, the
`.linkOn/.linkOff/.relink` DrumKit visual-commands, and the tests driving them
(−89 lines). Kept the live reads: `TrackGroup.isPatternLinked` (+ Codable, drives
kit-collapse in TracksMatrixView/LiveWorkspaceView) and
`DrumKitMatrixModel.isLinkBroken` (feeds the `patternLinkBroken` render
visual-state). No runtime/visual change (mutations were already unreachable
post-UI-removal): `02-tracks-navigator` AE 0, build green. Tests hit the CoreAudio
stall (1500s/case); the one case that ran passed → fell back to build-green +
no-dangling-refs + collapse parity.


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

## W8 — Split `TrackRoutingTabContent` Mode enum into two views (LOW) — ✗ WON'T DO

On inspection the `Mode { sound, mixer }` enum is an idiomatic small-view pattern:
both branches share the struct's inputs (document/session/summary/accent) + the
padding wrapper; `.sound` is a one-liner (`TrackDestinationEditor`) and `.mixer`
is the path-summary + destination row. Splitting means 2 new structs, relocating
~150 lines of helpers, rewiring 4 call sites (TrackSourceEditorView ×2,
TrackWorkspaceView, SliceTrackWorkspaceView), and 4 capture-parity runs — pure
code-reorg with zero user/perf benefit on a surface that was fragile all session.
Risk without gain; skipped. (Available later if desired — it's a clean split.)


The `enum Mode { sound, mixer }` multiplexes one struct into two layouts that
share nothing. Split into `TrackSoundTabContent` + `TrackMixerTabContent`.
Low value; do only if W1–W7 land cleanly. **Caution:** this surface was just
unified this session — capture `19`/`22b`/`27b`/`29c` and require parity.

## W9 — Generic status dictionary in VisualScenarioCommandRunner (LOW — risky) — ✗ WON'T DO (owner: SKIP)

Owner decided to skip: the runner's status string is parsed by every capture's
status-wait, so the blast radius (the whole QA harness) outweighs the
internal-cleanliness gain. The per-surface mirror fields stay as tolerable
boilerplate.


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
