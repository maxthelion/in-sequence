# Clip UI Tidy + Per-Pattern Lazy Clips

**Date:** 2026-04-21
**Status:** Design — not yet implemented
**Relates to:** `Sources/UI/TrackSource/TrackSourceEditorView.swift`, `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`, `Sources/UI/TrackSource/TrackPatternSlotPalette.swift`, `Sources/Document/Project+TrackSources.swift`, `docs/plans/2026-04-21-per-track-owned-clips-opt-in-generators.md`

## Goal

Ship three narrowly-scoped UI and data-layer fixes that make the Track workspace's Clip panel less confusing today, **without** touching the ambiguous `StepSequenceTrack.stepPattern` / `ClipContent.stepSequence.stepPattern` dual storage — that is scoped to a separate investigation (`2026-04-XX-step-pattern-clip-model-review.md`).

1. **Remove the "Clip: [Main Track clip ▼]" dropdown** from the Track workspace's Clip panel.
2. **Remove the "60, 62, 64, 67" pitches text field** that currently appears at the bottom of the same panel.
3. **Make each pattern slot own its own clip, lazily.** Today `TrackPatternBank.default(for:initialClipID:)` seeds every slot with the same `initialClipID`, which is why editing "pattern 2" appears to edit "pattern 1" (they're the same clip). After this change, only slot 0 starts with a clip; slots 1–15 start empty and allocate a fresh clip the first time the user toggles a step in that slot.
4. **Update the pattern palette's occupancy indicator** from "scheduled in some phrase" to "has stored clip with non-empty content".

**Verified by:** On the Track workspace, open a fresh mono track. The Clip panel shows the pattern palette + step editor. No "Clip" dropdown. No comma-separated pitches text field. Palette button 1 is visually filled (has the seeded default clip); buttons 2–16 are visually empty. Select pattern 2; toggle step 4; palette button 2 becomes filled. Select pattern 1; its seeded clip is unchanged. Select pattern 3; it is still empty — toggling pattern 2 did not affect it.

## Non-goals

- Changing `StepSequenceTrack.stepPattern` / `stepAccents` semantics, or touching the dual-storage situation with `ClipContent.stepSequence`. That is the explicit subject of the separate step-pattern / clip model review spec. Until that review lands, we keep the existing shape.
- Introducing a piano-roll editor. Deferred.
- Paging the step grid for >16 steps. Deferred.
- Per-clip length changes. Deferred.
- Unifying `ClipContent` cases (`.stepSequence` / `.pianoRoll` / `.sliceTriggers`). Deferred.
- Save-format migration. Existing documents continue to decode exactly as before. Slots that today have all-same `clipID` across 16 positions still decode correctly — the lazy behavior only applies to *newly-created* tracks and newly-cleared slots; saved projects with the old shared-clip shape continue to render, and editing any slot still mutates the shared clip (for now).
- Drum-kit seed path changes. `addDrumKit(plan:)` / `addDrumKit(_:)` still seed all their member tracks with clips on slot 0 in the current shape.
- Chord / micro-timing / fill support per step. Those are Plan 2 review topics.
- Copy / paste / duplicate patterns.

## Principle

The Clip panel today exposes two controls that don't match the mental model:
- A "Clip" dropdown that lets the user switch which `ClipPoolEntry` a slot references. This treats clips as reusable across tracks, which isn't the user's intent.
- A pitches text field (`"60, 62, 64, 67"`) that edits `ClipContent.stepSequence.pitches` — a clip-wide chord that every "on" step plays. Awkward, and redundant with the track-level pitches concept elsewhere in the UI.

Removing both controls narrows the panel to the one thing users actually do there: pick a pattern button, then edit its steps. The lazy-allocation fix turns the pattern buttons into what they already visually suggest — separate patterns, not 16 aliases for one clip.

The palette occupancy indicator change brings the visual state in line with the new semantics. Today a slot "lights up" when some phrase's layer cell points at that `patternIndex` — which is essentially disconnected from whether the slot has content. After the change, a slot lights up iff it owns a clip with at least one active step (or, for other `ClipContent` variants, non-empty equivalent state).

## Architecture

Five surfaces changed, one helper added. No engine-side changes.

### 1. `TrackSourceEditorView.swift` — drop the clip dropdown

Delete the `Picker("Clip", selection: clipIDBinding)` block (currently around lines 118–124 in `Sources/UI/TrackSource/TrackSourceEditorView.swift`) and its `clipIDBinding` computed property (currently around lines 161–169). The view's body becomes: pattern palette → step editor → (no other controls under the palette).

The `StudioPanel(title: "Clip", eyebrow:...)` remains, but its `eyebrow` text simplifies from "Direct clip source" / "No clip selected" to a single "Pattern editor" label (or the track's name — to be nailed down during implementation).

### 2. `ClipContentPreview.swift` — drop the pitches text field

Delete the `TextField(...)` under `case .stepSequence` (currently around lines 25–40 in `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`) that edits the clip's `pitches` via comma parsing. Other `ClipContent` cases in this file (e.g. `.pianoRoll`, `.sliceTriggers` preview rows) are left as-is.

The file keeps its non-editing preview render (whatever visualization of the step pattern it has); only the comma-text editor goes away.

### 3. `TrackPatternBank.default(for:initialClipID:)` — lazy seeding

Change the static factory in `Sources/Document/PhraseModel.swift:546–556` from:

```swift
static func `default`(for track: StepSequenceTrack, initialClipID: UUID?) -> TrackPatternBank {
    let sourceRef = SourceRef(mode: .clip, generatorID: nil, clipID: initialClipID)
    return TrackPatternBank(
        trackID: track.id,
        slots: (0..<slotCount).map { TrackPatternSlot(slotIndex: $0, sourceRef: sourceRef) },
        attachedGeneratorID: nil
    )
}
```

to:

```swift
static func `default`(for track: StepSequenceTrack, initialClipID: UUID?) -> TrackPatternBank {
    let seededRef = SourceRef(mode: .clip, generatorID: nil, clipID: initialClipID)
    let emptyRef = SourceRef(mode: .clip, generatorID: nil, clipID: nil)
    let slots: [TrackPatternSlot] = (0..<slotCount).map { index in
        TrackPatternSlot(slotIndex: index, sourceRef: index == 0 ? seededRef : emptyRef)
    }
    return TrackPatternBank(trackID: track.id, slots: slots, attachedGeneratorID: nil)
}
```

Slot 0 keeps its seeded clip (so the default view on a new track isn't blank); slots 1–15 start `clipID = nil`. This only affects bank *creation*, not decoded saved banks.

### 4. `Project+TrackSources.swift` — `ensureClipForCurrentPattern`

Add to `Sources/Document/Project+TrackSources.swift`:

```swift
@discardableResult
mutating func ensureClipForCurrentPattern(trackID: UUID) -> UUID? {
    let slotIndex = selectedPatternIndex(for: trackID)
    guard let bankIndex = patternBanks.firstIndex(where: { $0.trackID == trackID }) else {
        return nil
    }
    let bank = patternBanks[bankIndex]
    let slot = bank.slot(at: slotIndex)
    if let existing = slot.sourceRef.clipID {
        return existing
    }

    guard let track = tracks.first(where: { $0.id == trackID }) else {
        return nil
    }
    let newClip = ClipPoolEntry(
        id: UUID(),
        name: "\(track.name) pattern \(slotIndex + 1)",
        trackType: track.trackType,
        content: .stepSequence(
            stepPattern: Array(repeating: false, count: 16),
            pitches: track.pitches
        )
    )
    clipPool.append(newClip)

    let merged = SourceRef(mode: .clip, generatorID: slot.sourceRef.generatorID, clipID: newClip.id)
    setPatternSourceRef(merged, for: trackID, slotIndex: slotIndex)

    return newClip.id
}
```

The function is idempotent: calling it when the slot already has a clip returns the existing ID without mutating the project. Calling it when the slot is empty allocates a fresh clip, appends to `clipPool`, and writes the new `clipID` into the slot's `SourceRef` via the existing `setPatternSourceRef(_:for:slotIndex:)` helper. The returned ID is the clip that subsequent step-toggle logic should mutate.

Content type is always `.stepSequence` with an all-false pattern of length 16 and `pitches` copied from the track. This matches the status-quo seed shape; the investigation spec will later propose a different shape.

### 5. Step-grid edit site — call `ensureClipForCurrentPattern` before mutating

Find the view that renders the 16-cell step grid. Current guess based on the repo layout is `Sources/UI/TrackSource/Clip/*` — likely `StepGridView` or similar. The gesture handler that today mutates either `document.project.tracks[i].stepPattern[cell]` or the clip's `stepPattern[cell]` needs a preamble:

```swift
let clipID = document.project.ensureClipForCurrentPattern(trackID: trackID)
guard let clipID else { return }
document.project.updateClipEntry(id: clipID) { entry in
    guard case var .stepSequence(stepPattern, pitches) = entry.content else { return }
    stepPattern[cellIndex].toggle()
    entry.content = .stepSequence(stepPattern: stepPattern, pitches: pitches)
}
```

This guarantees the clip exists before the write. The exact code depends on what the current step-grid mutation actually does — see the implementation plan for the concrete edit. This is the plan's riskiest touch because we don't yet know whether the current step grid writes to `track.stepPattern`, `clip.stepPattern`, or both; the implementation task enumerates the current write sites and adapts each.

### 6. `TrackPatternSlotPalette.swift` — occupancy reflects stored content

Change the palette's "filled vs empty" predicate. Today it consults `occupiedPatternSlots` (computed from `phrases.map { patternIndex(...) }`). After:

```swift
private func isOccupied(slotIndex: Int, bank: TrackPatternBank, clipPool: [ClipPoolEntry]) -> Bool {
    guard let clipID = bank.slot(at: slotIndex).sourceRef.clipID,
          let clip = clipPool.first(where: { $0.id == clipID })
    else {
        return false
    }
    return !clipIsEmpty(clip.content)
}

private func clipIsEmpty(_ content: ClipContent) -> Bool {
    switch content {
    case let .stepSequence(stepPattern, _), let .sliceTriggers(stepPattern, _):
        return stepPattern.allSatisfy { !$0 }
    case let .pianoRoll(_, _, notes):
        return notes.isEmpty
    }
}
```

The "scheduled in some phrase" concept is preserved elsewhere (phrase workspace), but the pattern palette no longer uses it.

## Data flow

1. User opens a fresh track. `TrackPatternBank.default(...)` runs; slot 0 has a clip, slots 1–15 have `clipID = nil`.
2. Pattern palette renders: button 1 filled (seeded clip with default content), buttons 2–16 empty.
3. User taps pattern 2. `setSelectedPatternIndex(1, for:)` updates the phrase's patternIndex layer, same as today. No clip allocation yet.
4. Step grid renders in its empty state (all cells off).
5. User taps step 4. The handler calls `document.project.ensureClipForCurrentPattern(trackID:)`, which allocates a fresh clip, appends to `clipPool`, and writes the new `clipID` into slot 1's `SourceRef`. Then the handler mutates the clip's `stepPattern[4] = true`.
6. Pattern palette re-renders: button 2 now filled (its clipID is non-nil and its stepPattern has an active step).
7. User taps pattern 1: the seeded clip renders unchanged.
8. User taps pattern 3: empty. User taps step 4 in pattern 3: a *different* clip is allocated (new UUID); patterns 2 and 3 are now independent.

## Error handling

- **Step tap on a track whose `patternBanks` entry is missing (shouldn't happen but defensive):** `ensureClipForCurrentPattern` returns `nil`; the step-grid handler bails with no mutation. Logged via `NSLog` (single line with `trackID`).
- **Step tap during playback:** unchanged from today's behavior. The clip mutation flows through `document.project` → `EngineController.apply(documentModel:)`. Delta-based apply (planned separately) will reduce the per-edit cost; this plan doesn't depend on it.
- **Seeded slot 0 clip removed externally:** if slot 0's `clipID` is deleted from `clipPool`, `ensureClipForCurrentPattern` treats slot 0 the same as any empty slot and allocates a fresh clip on next edit. The palette would show slot 0 as empty until that edit happens. Acceptable — no crash, no data loss.
- **Two UI writers racing on the same track's pattern bank:** SwiftUI bindings serialize on main, so the second write sees the first's mutation. No concurrent write scenario.

## Testing

### Unit tests (Document layer)

`Tests/SequencerAITests/Document/TrackPatternBankDefaultSeedingTests.swift` — new file:

- `TrackPatternBank.default(for:initialClipID:)` with a non-nil `initialClipID` → slot 0's `clipID == initialClipID`; slots 1..15 `clipID == nil`.
- Same with `initialClipID == nil` → slot 0's `clipID == nil`; slots 1..15 `clipID == nil`.
- Every slot's `mode == .clip`; every slot's `generatorID == nil`.
- `attachedGeneratorID == nil`.

`Tests/SequencerAITests/Document/ProjectEnsureClipForCurrentPatternTests.swift` — new file:

- On a fresh project with a mono track (slot 0 seeded, slots 1–15 empty), calling `ensureClipForCurrentPattern` after `setSelectedPatternIndex(1, ...)` allocates a new clip; its ID matches the slot's `clipID`; clipPool count increases by 1.
- Calling `ensureClipForCurrentPattern` again on the same slot returns the *same* ID; clipPool count unchanged (idempotent).
- Calling on two different slots produces two distinct clipIDs; clipPool count increases by 2.
- Calling for a trackID that isn't in `patternBanks` returns `nil`; clipPool unchanged.
- The allocated clip's `content` is `.stepSequence(stepPattern: all-false of length 16, pitches: track.pitches)`.
- The allocated clip's `trackType` matches the track's `trackType`.

`Tests/SequencerAITests/Document/ClipIsEmptyTests.swift` — new file:

- `.stepSequence` with all-false stepPattern → empty.
- `.stepSequence` with any true step → non-empty.
- `.sliceTriggers` analogously.
- `.pianoRoll` with `notes.isEmpty` → empty.
- `.pianoRoll` with non-empty notes → non-empty.

### UI (manual smoke)

1. Open a fresh project; add a mono track. Verify:
   - Clip panel shows no dropdown.
   - No pitches text field under the grid.
   - Pattern palette button 1 is visually filled; buttons 2–16 are empty.
2. Tap pattern 2, toggle step 4 → palette button 2 becomes filled.
3. Tap pattern 1 → seeded clip unchanged (confirm no accidental cross-mutation).
4. Tap pattern 3 → empty. Toggle step 2 → palette button 3 becomes filled. Confirm patterns 2 and 3 are independent.
5. Clear all steps in pattern 2 (toggle the one on-step off) → palette button 2 returns to empty state (because `clipIsEmpty(content)` is now true, even though the clipID is retained).
6. Add a drum kit → each member track's palette button 1 is filled with the seeded pattern; buttons 2–16 empty.
7. Open a previously-saved project that used the old shared-clip shape → it decodes and renders; every pattern's palette button reports occupancy based on the shared clip's content (so buttons 1..16 are either all filled or all empty, reflecting the saved-shape reality). No crash.

### Visual regression guard

Screenshot the Clip panel + pattern palette before / after; diff. The expected delta is the removed dropdown + removed text field + changed palette occupancy colors. Anything else is unintended.

## Scope

Single plan, ~5 files touched, ~3 new test files. No engine changes. No save-format changes. Tag `v0.0.26-clip-ui-tidy` at completion.

## Decisions taken

- **Slot 0 keeps its seeded clip; slots 1–15 start empty.** Alternative (all slots empty) was rejected because a fresh track would have an entirely blank editor until the user clicks, which is worse for onboarding.
- **Lazy clip allocation triggers on first step toggle**, not on pattern-button tap. Tapping a pattern selects it without mutating the document; only an actual edit commits a clip to the pool. Matches user preference for "don't save until I add steps".
- **`ensureClipForCurrentPattern` returns `UUID?`** (not throws / fatalError) so defensive call sites can silently no-op without crashing. Missing pattern-bank is logged but doesn't propagate.
- **Palette occupancy = has-content**, not is-scheduled. The is-scheduled indicator is preserved elsewhere in the phrase workspace if needed; on the Track editor the content view is what matters.
- **Initial clip content shape is `.stepSequence(all-false × 16, track.pitches)`.** Matches today's seed; the step-pattern / clip model review spec will propose a different shape and Plan 3 will migrate.
- **Name for the auto-allocated clip** is `"<track name> pattern N"` with `N = slotIndex + 1`. Simple, identifiable in a debug inspector. Not user-editable in this plan.
- **Saved-project compatibility without migration:** the old shared-clip shape continues to decode and render. The palette shows occupancy per-slot based on the shared clip's content (so either all 16 report filled or all 16 report empty). This is technically a visual change for saved projects but is correct per the new semantics. If a user wants independent patterns on a saved project, they can delete the saved track and re-add it, or a future migration plan can split shared clips apart.
- **Drum-kit seeding is unchanged in this plan.** Every drum-track member still gets slot 0 seeded with `.stepSequence` content. The drum-kit modal plan's `DrumGroupPlan.prepopulateClips` toggle continues to work.
