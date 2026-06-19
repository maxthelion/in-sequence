# Goal: track-view-ia review follow-up

Source: comprehensive code review of `main` (2026-06-19) after merging
`auto/roadmap-track-view-ia` and `fix/scenes-fx-filter`, graded against
`wiki/pages/code-review-checklist.md` and `wiki/pages/architecture-guardrails.md`.

The engine-stability and architecture-discipline classes came through clean
(graphLock re-entry, Performance-Time Mutation Rule, document-truth-vs-transient
state all verified OK). The debt is concentrated in one half-wired feature
(per-track FX) and one oversized file (`DrumKitMatrixView`), plus test gaps.

**Process for every slice:** work in a worktree off `main`; build green
(`xcodebuild ... build`) before each commit; one logical change per commit with
the standard trailers; restore `Sources/Resources/Info.plist` from HEAD if
xcodegen runs. Do not regress the verified-clean classes above.

---

## W1 — Per-track FX: make it real or honest (CRITICAL)

`StepSequenceTrack.fxInserts` is Codable and written to `.seqai`, exposed in
three UI entry points (slicer FX tab, melodic FX tab, AC21 expanded-row "+FX"),
but the engine never reads it (`grep fxInserts Sources/Engine Sources/Audio`
returns nothing). Users author inert state. Kit-*bus* FX is fine; this is
per-*track* FX only.

**Preferred:** wire `track.fxInserts` into the audio graph via a per-track
insert host that mirrors `MixerBusHost` (attach AU/native nodes in series on the
track's output before its bus/master route), driven by a scoped runtime update
(NOT a per-gesture full document apply — see Performance-Time Mutation Rule).

**Acceptable fallback** (if wiring is out of scope for one slice): gate the three
UI surfaces so a track FX chain cannot be authored, or label them clearly as
"not yet audible", so no inert state enters the document.

**Acceptance criteria**
- AC1.1 Adding an insert to a track audibly changes that track's output (manual
  QA note acceptable) **or** the FX surfaces are visibly gated/labelled as
  inert and authoring is blocked.
- AC1.2 The insert chain mutation path is scoped runtime + debounced persist, not
  `apply(documentModel:)` per gesture.
- AC1.3 `TrackFXInsertTests` covers: add/remove/reorder/bypass via the public
  `SequencerDocumentSession` surface; `TrackFXInsert.normalizedChain` UUID-dedupe;
  empty-name → `kind.defaultName`; Codable round-trip incl. legacy doc missing
  the `fxInserts` key decoding to `[]`.

## W2 — De-god-file `DrumKitMatrixView` (CRITICAL)

`Sources/UI/DrumGroup/DrumKitMatrixView.swift` is 3,652 lines / ~10
responsibilities. (Companion smells: `SliceTrackWorkspaceView` 1,457,
`TrackSourceEditorView` 1,386, `SliceTrackEditingControls` 1,105 — address if
time permits; `DrumKitMatrixView` is the priority.)

**Acceptance criteria**
- AC2.1 `DrumKitMatrixModel` extracted to `DrumKitMatrixModel.swift` (no SwiftUI
  import) and covered by at least one unit test that previously couldn't exist.
- AC2.2 Capture/history surface, expanded-row accordion, and the routing editor
  each moved to their own files under `Sources/UI/DrumGroup/`.
- AC2.3 `DrumKitMatrixView.swift` left under ~700 lines as a composition root.
- AC2.4 Zero behavior change; build green; existing `DrumKitMatrixEditingTests`
  still pass.

## W3 — Close the test gaps on new behavior (IMPORTANT)

**Acceptance criteria**
- AC3.1 Bar pager: extract `barPageCount`/`clampedPage` from the view to a free
  function or value type; test boundaries 0 / 16 / 17 / 32 steps and
  clamp-after-shrink.
- AC3.2 Scoped perform: session test that `enterScopedPerform([t1])` sets
  `performTrackScope == {t1}` and `workspaceMode == .perform`;
  `enterScopedPerform([])` clears scope (empty = unscoped = all tracks).
- AC3.3 `SamplerFilterNode`: extend the type-mapping test to assert
  `.peak → .parametric` and `.comb`/`.formant → .bandPass`.
- AC3.4 `DrumGroupPlanFactoryTests` asserts `busRouting == .dedicatedBus` default.

## W4 — Type the QA command surface + delete dead code (IMPORTANT)

**Acceptance criteria**
- AC4.1 Replace `applyVisualCommand(_ command: String)` with an
  `enum DrumKitVisualCommand`; the runner maps strings → enum at the boundary;
  drop the dead `display-16`/`display-32` legacy cases.
- AC4.2 Delete `refreshClipHistoryWhileVisible()` (no-op body), its
  `clipHistoryLiveRefreshKey` constant, and the dead `.task(id:)` in
  `TrackSourceEditorView.swift` — or restore the intended poll if still wanted.

## W5 — Hygiene minors (MINOR — batch into one or two commits)

**Acceptance criteria**
- AC5.1 Extract the nested ternary at `TrackPatternSlotPalette.swift:88` to a
  computed `String` (type-check-timeout risk class).
- AC5.2 Replace the `postRenderedVisualState` `[String: Any]` payload with a
  typed struct; drop the `-1` "no expanded part" sentinel in favour of optional.
- AC5.3 Name the duplicated `prefix(16)` effect-menu cap as one constant.
- AC5.4 Surface (not swallow) audio-load failures on the slicer *user-action*
  paths (`attachLoop`, `audition`) — set `analysisMessage` or log a breadcrumb;
  name the `44_100` rate fallback or return optional.
- AC5.5 Relabel macro M1 from "direction" to "start"/"position" (it drives
  `sampleStart`); label or remove the inert Kit Macros tab and Kit Mixer send
  badges so they don't read as finished controls.

---

## Out of scope
- The pre-existing `MixerBusHost` `cachedAUEffects`/`pendingAUEffectIDs` prune-on-
  removal leak (not touched by this merge — file separately if desired).
- The companion slicer/track-source god-files (W2 lists them as stretch only).
