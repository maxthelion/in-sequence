# Tracks Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the dedicated `Tracks` workspace as the matrix-style entry point into track creation and selection. It should reflect the fresh document model: flat tracks, optional `TrackGroup` membership, immutable track type, and first-class drum-kit creation.

**Architecture:** `TracksMatrixView` renders the document's flat `tracks: [StepSequenceTrack]` list in an adaptive matrix. There is no `trackSlots` structure. Each card routes into the single-track workspace. Group membership is shown by tint, label, and optional collapse/expand affordances; drum kits are not a special track type.

**Tech Stack:** Swift 5.9+, SwiftUI (`LazyVGrid`, sheets, context menus), Foundation, XCTest.

**Parent spec:** `/Users/maxwilliams/dev/sequencer-ai/docs/specs/2026-04-18-north-star-design.md`

**Status:** ✅ Completed 2026-04-19. Tag `v0.0.10-tracks-matrix`. Verified with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project /Users/maxwilliams/dev/sequencer-ai/SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS,arch=arm64' test` (`174` tests, `0` failures, `3` skips).

**Depends on:**

- `2026-04-19-track-group-reshape.md`

**Deliberately deferred:**

- Multi-select / bulk actions
- Drag-reordering tracks
- Deep group-edit UI (rename group, reassign members, recolor)

---

## File Structure

```
Sources/
  UI/
    TracksMatrixView.swift
    DetailView.swift
    StudioTopBar.swift
  Document/
    SeqAIDocumentModel.swift
    TrackGroup.swift
Tests/
  SequencerAITests/
    Document/
      SeqAIDocumentTests.swift
    UI/
      TracksMatrixViewTests.swift
```

---

## Task 1: Matrix shell + navigation

**Scope:** The `Tracks` workspace should be a real matrix surface, not just a placeholder panel.

**Files:**

- Modify: `Sources/UI/TracksMatrixView.swift`
- Modify: `Sources/UI/DetailView.swift`

**Done when:**

1. The matrix renders the current flat track list.
2. Clicking a card selects that track and routes to `.track`.
3. The selected track is visibly distinct.
4. Empty-state messaging is only shown when there are truly no tracks.

- [x] Add `Tracks` workspace shell
- [x] Tighten the matrix layout and card hierarchy
- [x] Add focused tests for selection/navigation

---

## Task 2: Minimal identity cards

**Scope:** Cards should identify tracks quickly without duplicating the whole track editor. The matrix is for choosing and creating tracks, not for editing every parameter inline.

**Files:**

- Modify: `Sources/UI/TracksMatrixView.swift`
- Create or modify small helper views if needed

**Done when:**

1. Each card shows track name and type glyph/label.
2. Grouped tracks share a visual tint or pill.
3. The card does not duplicate destination controls or generator parameters.
4. Drum-kit members read as tracks in a group, not as a special legacy drum type.

- [x] Simplify card contents
- [x] Add group tint / group label treatment
- [x] Keep selection styling clear

---

## Task 3: Creation affordances

**Scope:** Creation should follow the new type model exactly.

**Files:**

- Modify: `Sources/UI/TracksMatrixView.swift`
- Modify: `Sources/Document/SeqAIDocumentModel.swift`
- Modify: `Tests/SequencerAITests/SeqAIDocumentTests.swift`

**Creation actions:**

- `Add Mono Track`
- `Add Poly Track`
- `Add Slice Track`
- `Add Drum Kit`

**Done when:**

1. Mono / Poly / Slice create one new flat track.
2. Drum Kit uses `addDrumKit(_:)` and appends a grouped set of mono tracks.
3. New tracks become selected and route into Track view.
4. No UI path exposes the retired `drumRack` type.

- [x] Implement document-backed create actions
- [x] Add drum-kit create affordance
- [x] Cover selection after creation in tests

---

## Task 4: Group-aware matrix behavior

**Scope:** The matrix should make grouped tracks legible without reintroducing fake hierarchy.

**Files:**

- Modify: `Sources/UI/TracksMatrixView.swift`
- Modify: `Sources/Document/TrackGroup.swift` only if helper accessors are needed

**Done when:**

1. Grouped members are clearly visually related.
2. A group can optionally render with a compact aggregate header or badge.
3. Selecting one grouped member still opens that exact track in Track view.
4. The surface remains flat and dense enough to scan quickly.

- [x] Add group summary treatment
- [x] Add optional collapse/expand behavior if needed
- [x] Keep member selection explicit

---

## Task 5: Closure

**Verification command:**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project /Users/maxwilliams/dev/sequencer-ai/SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS,arch=arm64' \
  test
```

- [x] Full suite green
- [x] Wiki notes updated if behavior changed materially
- [x] Plan marked complete
- [x] Tag: `git tag -a v0.0.10-tracks-matrix -m "Tracks matrix complete"`
