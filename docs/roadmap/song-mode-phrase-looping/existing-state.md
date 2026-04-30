# Song Mode And Phrase Looping — Existing State

## Summary

The `TransportMode` enum and supporting UI exist in production, but neither the model nor the engine exposes anything needed by this feature's user stories. There is no current-phrase observable on `EngineController`, no queued-next-phrase state anywhere in the system, and `transportMode` is not connected to the tick engine at all. The three views that need to track the "active phrase" each carry independent copies of the same untested derivation logic.

---

## Transport Mode Model

**File:** `Sources/Engine/TransportMode.swift`

`TransportMode` is a two-case enum (`song`, `free`). Its `detail` strings describe the intent: `.song` → "Transport follows phrase order", `.free` → "Transport stays on the current phrase." The enum is `Codable`, `CaseIterable`, and `Equatable`.

`EngineController` holds `private(set) var transportMode: TransportMode = .free` and exposes `setTransportMode(_ mode:)`, which is a plain assignment with no side-effects on the tick engine or playback snapshot. The engine's `prepareTick` always reads `playbackSnapshot.selectedPhraseID` regardless of `transportMode`; the mode value is currently only consumed by two UI views to decide which phrase to display as the "basis phrase."

**Gap:** `transportMode` has no effect on what the engine actually plays. The `.song` label implies a scripted arrangement, but nothing enforces that semantic. From the engine's perspective, `.song` and `.free` are identical.

---

## Phrase Navigation — Duplicated View-Side Logic

Three views independently derive `playbackPhraseIndex` from the absolute tick counter. The logic is identical in each:

1. `Sources/UI/TracksMatrixView.swift` — `editingPhraseID` (lines 77–87), `playbackPhraseIndex` (lines 89–112)
2. `Sources/UI/LiveWorkspaceView.swift` — `editingPhraseID` (lines 34–43), `playbackPhraseIndex` (lines 46–69)
3. `Sources/UI/PhraseWorkspaceView.swift` — `playbackPhraseIndex` (lines 44–66)

All three compute:

```
absoluteBar = transportTickIndex / stepsPerBar
cycleBar = absoluteBar % totalBars   (totalBars = sum of phrase.lengthBars)
walk phrases until cycleBar is consumed → return that index
```

This is the `.song`-mode cycling algorithm: it treats all phrases as a flat, ordered playlist looped end-to-end. In `.free` mode the result is derived but then ignored — `editingPhraseID` returns `session.store.selectedPhraseID` when not in `.song` mode.

**Gap for free-play stories:** There is no concept of "current free-play phrase" in the engine; in `.free` mode the tick engine loops `selectedPhraseID` forever and the derived `playbackPhraseIndex` is discarded. No signal flows from phrase boundaries back to the UI or the model.

---

## Transport Bar — No Phrase Indicator

**File:** `Sources/UI/TransportBar.swift`

Current top-bar contents (left to right):
- Play/stop button
- Record button (disabled)
- BPM label + slider + numeric readout
- `TransportModePicker` (Song / Free toggle)
- Transport position string (`bar:beat:step`)
- Note-activity indicator dot
- `statusSummary` text

There is no current-phrase label, no queued-phrase button, and no dropdown. The `TransportBar` reads from `EngineController` but `EngineController` exposes no current-phrase or queued-phrase observable.

---

## Queued-Next-Phrase State

No queued-phrase field exists anywhere:
- `Project` (document model) has `selectedPhraseID` only.
- `PlaybackSnapshot` has `selectedPhraseID` only.
- `EngineController` has no published phrase-queue state.
- No `SequencerDocumentSession` mutation touches a "next phrase" concept.

The tick engine in `prepareTick` reads `playbackSnapshot.selectedPhraseID` and steps through that phrase's buffer indefinitely; it has no end-of-cycle callback or phrase-boundary event that could trigger a queued switch.

---

## "Song Mode" — Resolution of the Open Question

The open question in `user-stories.md` was: is "Song Mode" (a fully scripted linear arrangement) a distinct sub-feature, or is it just the existing `.song` transport mode?

**Finding:** The existing `.song` mode is a stub. The enum and the label exist, and the three view-side derivations embody a "play phrases in sequence" algorithm, but:
- The tick engine ignores `transportMode`.
- No arrangement data (ordering, repeat counts, cue conditions) exists in the model.
- The three views' `playbackPhraseIndex` derivation uses raw `lengthBars` from all phrases in document order — there is no scripted arrangement data structure at all.

What the views call `.song` mode today is better described as "auto-advance through all phrases in document order." A true scripted arrangement (user-defined sequence, per-phrase repeat counts, conditional triggers) would require new model structures and is not represented anywhere in the codebase.

**Conclusion:** "Song Mode" as a fully scripted linear arrangement is a separate, unbuilt feature. It is not this roadmap item. The stories in `user-stories.md` are correctly scoped to free-play phrase navigation (Stories 1–5), which maps to `.free` mode. The `.song` mode label is currently a misnomer for an auto-cycling behaviour that this item does not need to change.

---

## Architecture Constraints

- `EngineController` is `@Observable`. New observable properties (e.g. `currentPhraseID`, `queuedPhraseID`) can be added as `private(set) var` fields with no threading risk if written via `publishToMain`.
- The tick engine's phrase boundary is implicit: step `transportTickIndex % phraseStepCount == phraseStepCount - 1`. An end-of-cycle hook would need to be detected in `prepareTick` and published to main.
- `setTransportMode` is a synchronous main-thread assignment with no snapshot invalidation; adding a queued-phrase field can follow the same lightweight pattern.
- `PlaybackSnapshot` is `Sendable` and value-typed. Adding `queuedPhraseID: UUID?` is straightforward but requires updating `SequencerSnapshotCompiler.compile`.
- The Tracks UI basis phrase currently reads `session.store.selectedPhraseID` in `.free` mode. Updating it when a phrase is cued requires either a new `SequencerDocumentSession` mutation (which persists to the document) or a separate live-performance state on `EngineController` that the view prefers over `session.store.selectedPhraseID`.

---

## Model Gaps vs UX/Workflow Gaps

| Gap | Kind | Where |
|-----|------|--------|
| No `currentPhraseID` published by `EngineController` | Model | `EngineController` |
| No `queuedPhraseID` state in engine or document | Model | `EngineController`, `Project`, `PlaybackSnapshot` |
| No end-of-cycle callback or phrase-boundary event | Engine | `EngineController.prepareTick` |
| Transport bar has no phrase indicator or queue button | UX | `TransportBar` |
| Three views duplicate phrase-cycling derivation logic | Architecture | `TracksMatrixView`, `LiveWorkspaceView`, `PhraseWorkspaceView` |
| Basis-phrase update on cue not wired | Workflow | `TracksMatrixView.editingPhraseID`, `LiveWorkspaceView.editingPhraseID` |
| `.song` mode label is misleading for free-play stories | Naming | `TransportMode`, `TransportBar` |

---

## Relevant Tests

**Existing:**
- `Tests/SequencerAITests/Engine/TransportModeTests.swift` — enum exhaustiveness, Codable roundtrip, label/detail non-empty. Does not test engine behaviour under either mode.

**Missing coverage:**
- No tests for `playbackPhraseIndex` derivation (currently view-only, untestable without rendering).
- No tests for phrase boundary detection.
- No tests for queued-phrase switching behaviour.
- No tests for `EngineController.setTransportMode` side effects (because there are none yet).
