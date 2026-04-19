# Tracks Matrix View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the app a dedicated Tracks matrix as a nav destination — a **fixed 8×8 grid of 64 slots**, each either empty or carrying a track. Existing-track slots show a card summarising that track (name, type badge, destination summary, pattern-slot strip preview, mute state) — clicking routes to its detail. Empty slots show an empty placeholder; clicking an empty slot pops a track-creation modal with each `TrackType` as a one-click button, creates the track into that slot, and navigates to its detail. From the matrix the user can also duplicate, delete, and (context-menu) "Change type…" a track. Verified by: navigating to the Tracks section shows 64 cells; clicking an empty slot creates a track of the chosen type at that slot index and routes to its detail; clicking a populated slot routes to the existing track's detail; deleting clears the slot; the `selectedTrackID` invariant never points at a deleted track (closes the codex review-queue finding).

**Architecture:** New SwiftUI view `TracksMatrixView` that renders a **fixed 8×8 `LazyVGrid`** of 64 cells. Slot-to-track mapping lives on the document as `trackSlots: [TrackID?]` of fixed length 64 — a stable positional layout that survives reorder. Tracks themselves still live in `tracks: [Track]` keyed by `id`; `trackSlots` is the one-to-one indexing into the grid. Empty cells render an `EmptyTrackCell`; populated cells render the existing `TrackCard`. `WorkspaceSection` gains a `.tracks` case alongside the existing `.song / .phrase / .track / .mixer / .perform / .library`. The studio chrome's section nav gets a new button. Clicking a populated card sets `document.model.selectedTrackID` and switches `section = .track`, routing to the existing single-track detail. Clicking an empty cell opens `CreateTrackSheet` — a row of large track-type buttons (Instrument / Drum / Slice). Picking one calls `document.model.createTrack(type:atSlot:)`, which populates per-type-default `Voicing` (from the `track-destinations` plan) and writes the new track's ID into `trackSlots[slotIndex]`. Navigation switches to `.track` and selects the new track.

Track-type is still **immutable in the data model** (spec §"Track types, patterns, and phrases"). The UI affords a "Change Type…" action via context menu which under the hood is "delete the old track from this slot + create a fresh one of the chosen type in the same slot." Existing phrase `trackPatternIndexes` entries referencing the old TrackID get cleaned up. The user sees this as "changed the track's type"; the data model sees a destroy + recreate — consistent with the spec's immutability stance while giving the user the affordance they expect.

The `selectedTrackID` invariant fix (from codex's review-queue) lands as part of this plan's init + deletion + slot-clearing code paths, since all of them touch the invariant.

**Tech Stack:** Swift 5.9+, SwiftUI (`LazyVGrid`, `onDrag` / `onDrop`), Foundation, XCTest.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` — §"UX surfaces" (the matrix-driven nav) + §"Track types, patterns, and phrases" (per-type behaviours the card summarises).

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**Status:** <STATUS_PREFIX> <COMPLETED_MARKER> TBD. Tag `v0.0.7-tracks-matrix` at TBD.

**Depends on:**

- `2026-04-19-track-destinations.md` — needs `Voicing` + `Destination` + `Voicing.defaults(forType:)` so the track-creation sheet populates correct defaults. Recommend executing after track-destinations lands. The cards' destination-summary pill also reads from `Voicing.defaultDestination`, which only exists after that plan.

**Deliberately deferred:**

- **Matrix-based track arrangement visualisation** (rendering the track's pattern output as a mini waveform / step preview). MVP cards show a minimal pattern-slot-strip preview; richer previews are a polish pass.
- **Drag tracks between projects.** Cross-project drag comes with a library UX plan.
- **Multi-select + bulk operations** (select 3 tracks, delete all, duplicate all). Single-select only in MVP.
- **Track-group / folder hierarchy.** Flat 64-slot grid for MVP.
- **Slot count > 64.** Fixed at 64 for MVP (8×8). Expanding to 128 / 256 / multi-bank (MPC-style 4 × 64 banks) is a later plan.
- **Slot labels.** MVP shows no per-slot label; a follow-up can add A1–H8 MPC-style coordinates if the UX calls for it.
- **Drag-to-swap** between slots. MVP's reorder is context-menu "Move to slot…" pickers; drag-drop between cells is finicky in `LazyVGrid` and deferred.

---

## File Structure

```
Sources/
  UI/
    TracksMatrixView.swift               # NEW — 8x8 LazyVGrid of 64 cells; populated or empty
    TrackCard.swift                      # NEW — populated-slot card component
    EmptyTrackCell.swift                 # NEW — empty-slot placeholder with "+" affordance
    CreateTrackSheet.swift               # NEW — type picker buttons at modal; called on empty-slot tap
    WorkspaceSection.swift               # MODIFIED — add .tracks case
    StudioTopBar.swift                   # MODIFIED — new nav button for .tracks
    ContentView.swift                    # MODIFIED — .tracks case in the section switch
  Document/
    SeqAIDocumentModel.swift             # MODIFIED — trackSlots: [TrackID?] (length 64) + slot-aware mutations + selectedTrackID invariant
Tests/
  SequencerAITests/
    Document/
      SeqAIDocumentModelTests.swift      # MODIFIED — trackSlots + invariant assertions (closes the codex review-queue item)
    UI/
      TrackCardTests.swift
      EmptyTrackCellTests.swift
      TracksMatrixViewTests.swift
      CreateTrackSheetTests.swift
    Snapshots/
      TracksMatrixSnapshotTests.swift    # skeleton; populated once qa-infra lands
```

**Constants:**

```swift
public enum TracksLayout {
    public static let slotCount: Int = 64
    public static let columnCount: Int = 8              // → 8 rows
    // slotIndex = row * columnCount + column
}
```

---

## Task 1: `WorkspaceSection.tracks` + nav button

**Scope:** Add the section case. Add the top-bar button. Wire `ContentView` to render (initially) an empty placeholder for `.tracks`.

**Files:**
- Modify: `Sources/UI/WorkspaceSection.swift` — add `case tracks`; update any `CaseIterable` display-order
- Modify: `Sources/UI/StudioTopBar.swift` — add a button with `.accessibilityIdentifier("section-tracks")`
- Modify: `Sources/UI/ContentView.swift` — switch for `.tracks` renders a placeholder
- Create: `Tests/SequencerAITests/UI/WorkspaceSectionTests.swift` — presence-of-tracks assertion

**Tests:**

1. `WorkspaceSection.allCases.contains(.tracks)`.
2. Case order: tracks comes after `.track` and before `.mixer` (or wherever sensible — document the chosen position).
3. `StudioTopBar` renders a button with identifier `"section-tracks"` (accessibility-tree test).

- [ ] Tests
- [ ] Implement
- [ ] `xcodebuild test` green
- [ ] Commit: `feat(ui): WorkspaceSection.tracks + top-bar nav button`

---

## Task 2: `SeqAIDocumentModel.selectedTrackID` invariant fix

**Scope:** Close the codex review-queue item `important-selected-track-id-invariant.md`. The issue: `SeqAIDocumentModel.init(version:tracks:selectedTrackID:)` stores the UUID verbatim, even when it doesn't exist in `tracks`. Normalisation currently only happens in `init(from:)`. Add the same normalisation to the memberwise init and to every mutation that could invalidate the invariant.

**Files:**
- Modify: `Sources/Document/SeqAIDocumentModel.swift`
- Modify: `Tests/SequencerAITests/Document/SeqAIDocumentModelTests.swift`

**Invariant (as a precondition):** `tracks.isEmpty || tracks.contains(where: { $0.id == selectedTrackID })`.

**Changes:**

- The memberwise init normalises: if `selectedTrackID` is not in `tracks`, fall back to `tracks[0].id` (when non-empty). If `tracks.isEmpty`, allow `selectedTrackID` to be any UUID (no track to select).
- Extract a `private mutating func normaliseSelection()` helper called from: memberwise init, `init(from:)`, `removeSelectedTrack`, `setTracks(_:)` if present, and anywhere else `tracks` is assigned.
- `selectTrack(id:)` already rejects invalid IDs — keep.
- `removeTrack(id:)` (new helper, referenced by Task 5 below) calls `normaliseSelection` after removing.

**Tests:**

1. `init(version: 1, tracks: [t1, t2], selectedTrackID: UUID())` where the random UUID isn't in tracks → `selectedTrackID == t1.id`.
2. `init(version: 1, tracks: [], selectedTrackID: <any>)` → `selectedTrackID` stays as-is (no crash).
3. Previously-buggy test `test_selected_au_output_routes_note_events_to_audio_sink` (flagged in codex's critique) — rewrite so the invariant is asserted explicitly AND the selected track ID is the real track created in the test, not a default.
4. After `removeSelectedTrack` on a 3-track doc: `selectedTrackID` is one of the remaining 2 track IDs.

- [ ] Tests
- [ ] Implement normalisation helper + call it from init + mutations
- [ ] Rewrite the flagged test
- [ ] Delete `.claude/state/review-queue/important-selected-track-id-invariant.md` in the same commit (marker the critique is closed)
- [ ] Green
- [ ] Commit: `fix(document): selectedTrackID invariant enforced in init + mutations`

---

## Task 3: `TrackCard` component (minimal — nav-focused)

**Scope:** The matrix is a navigation grid. Cards show *just enough* to identify the track at a glance — name + type indicator. No destination pill, no pattern preview, no mute state. Those live in the track detail view. Keeping cards minimal keeps the 8×8 grid legible at reasonable window sizes.

**Files:**
- Create: `Sources/UI/TrackCard.swift`
- Create: `Tests/SequencerAITests/UI/TrackCardTests.swift`

**View shape:**

```swift
struct TrackCard: View {
    let track: StepSequenceTrack
    let isSelected: Bool
    let onTap: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    let onChangeType: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                TrackTypeGlyph(type: track.trackType)       // the most prominent element — icon + colour per type
                Text(track.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(isSelected ? StudioTheme.cyan.opacity(0.25) : StudioTheme.border.opacity(0.1))
            .overlay(isSelected ? RoundedRectangle(cornerRadius: 6).stroke(StudioTheme.cyan, lineWidth: 2) : nil)
        }
        .contextMenu {
            Button("Duplicate", action: onDuplicate)
            Button("Change Type…", action: onChangeType)    // destructive: deletes + recreates
            Button("Delete", role: .destructive, action: onDelete)
        }
        .accessibilityIdentifier("track-card-\(track.id.uuidString)")
    }
}

struct TrackTypeGlyph: View {
    let type: TrackType
    // Renders a type-coloured icon (sf-symbol or custom):
    // - instrument   → "pianokeys" on cyan
    // - drumRack     → "circle.grid.3x3.fill" on magenta
    // - sliceLoop    → "waveform" on yellow
    // Type identity should be discernible in < 100ms at typical grid cell size.
}
```

**Tests:**

1. Renders the track's name (font-size 11, single line, truncating).
2. `TrackTypeGlyph` renders a different visual for each `TrackType`.
3. `.accessibilityIdentifier` matches `"track-card-\(track.id.uuidString)"`.
4. Tap calls `onTap` exactly once.
5. Context-menu Duplicate / Change Type… / Delete each wire to the right callback.
6. `isSelected = true` applies a different background + overlay than `isSelected = false`.

Explicitly NOT tested (because the card no longer shows them): destination text, pattern-preview cells, muted indicator.

- [ ] Tests
- [ ] Implement TrackCard + TrackTypeGlyph
- [ ] Green
- [ ] Commit: `feat(ui): TrackCard (minimal — type glyph + name only)`

---

## Task 4: `EmptyTrackCell` + `CreateTrackSheet`

**Scope:** Two tightly-coupled pieces. The empty-slot placeholder renders a subtle "+" affordance; tapping it opens a one-click type-picker modal. Picking a type creates the track at that slot and navigates to its detail. There is no name field — default names suffice; rename happens in the track detail view.

**Files:**
- Create: `Sources/UI/EmptyTrackCell.swift`
- Create: `Sources/UI/CreateTrackSheet.swift`
- Create: `Tests/SequencerAITests/UI/EmptyTrackCellTests.swift`
- Create: `Tests/SequencerAITests/UI/CreateTrackSheetTests.swift`

**Empty cell:**

```swift
struct EmptyTrackCell: View {
    let slotIndex: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack {
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(StudioTheme.mutedText.opacity(0.5))
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudioTheme.border.opacity(0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(StudioTheme.border.opacity(0.3),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("track-slot-\(slotIndex)-empty")
    }
}
```

**Create sheet:**

```swift
struct CreateTrackSheet: View {
    @Binding var isPresented: Bool
    let slotIndex: Int
    let onCreate: (TrackType) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Track in Slot \(slotIndex + 1)")
                .font(.title2)

            HStack(spacing: 16) {
                ForEach(TrackType.allCases, id: \.self) { type in
                    Button {
                        onCreate(type)
                        isPresented = false
                    } label: {
                        VStack(spacing: 8) {
                            TrackTypeGlyph(type: type)
                                .frame(width: 60, height: 60)
                            Text(type.label)
                                .font(.headline)
                        }
                        .frame(width: 140, height: 140)
                        .background(StudioTheme.border.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("create-track-\(type.rawValue)")
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 560)
    }
}
```

**Tests — EmptyTrackCell:**

1. Renders with accessibility identifier `"track-slot-\(slotIndex)-empty"`.
2. Tap calls `onTap` once.

**Tests — CreateTrackSheet:**

1. Renders one button per `TrackType` case (3 buttons in MVP: instrument / drumRack / sliceLoop).
2. Tapping the instrument button calls `onCreate(.instrument)` and sets `isPresented = false`.
3. Tapping the drum button calls `onCreate(.drumRack)` and dismisses.
4. Cancel dismisses without calling `onCreate`.
5. Each type button carries `.accessibilityIdentifier("create-track-\(type.rawValue)")`.

- [ ] Tests for EmptyTrackCell
- [ ] Tests for CreateTrackSheet
- [ ] Implement both views
- [ ] Green
- [ ] Commit: `feat(ui): EmptyTrackCell + CreateTrackSheet (one-tap type-picker)`

---

## Task 5: `SeqAIDocumentModel` — `trackSlots` + slot-aware mutations

**Scope:** Add the fixed-size `trackSlots: [TrackID?]` (length 64) to the document model. All track add / delete / duplicate / change-type operations target a specific slot index. Legacy documents decode into a packed trackSlots mapping — if a pre-trackSlots doc has N tracks, they occupy slots 0..N-1 and the rest are nil.

**Files:**
- Modify: `Sources/Document/SeqAIDocumentModel.swift`
- Modify: `Tests/SequencerAITests/Document/SeqAIDocumentModelTests.swift`

**New fields:**

```swift
public struct SeqAIDocumentModel: Codable, Equatable {
    public var version: Int
    public var tracks: [StepSequenceTrack]
    public var trackSlots: [TrackID?]              // length = TracksLayout.slotCount (64)
    public var selectedTrackID: UUID
    // ... existing fields
}
```

Invariant: `trackSlots.count == 64`. Every non-nil entry's ID exists in `tracks`. Every track's ID appears exactly once in `trackSlots`.

**API:**

```swift
/// The first empty slot, or nil if all 64 are full.
public var firstEmptySlot: Int? { get }

/// Track at the given slot, or nil if empty.
public func track(atSlot slotIndex: Int) -> StepSequenceTrack?

/// Create a new track of the given type at the specified empty slot.
/// Returns the new track ID, or nil if the slot is already occupied.
public mutating func createTrack(type: TrackType, atSlot slotIndex: Int, name: String? = nil) -> TrackID?

/// Remove the track at the given slot (if any). Slot becomes nil.
public mutating func removeTrack(atSlot slotIndex: Int)

/// Duplicate the track at `fromSlot` into `toSlot` (which must be empty).
/// Returns the new track ID, or nil on failure.
public mutating func duplicateTrack(fromSlot: Int, toSlot: Int) -> TrackID?

/// Move the track from one slot to another (swap if destination occupied).
public mutating func moveTrack(fromSlot: Int, toSlot: Int)

/// Change-type: destroy the track at `slotIndex` and create a fresh one of `newType`
/// at the same slot. Phrase references to the old track are cleaned up.
public mutating func changeTrackType(atSlot slotIndex: Int, newType: TrackType)
```

All mutations call a private `normaliseSelection()` helper (from Task 2) when the tracks list changes.

**`createTrack(type:atSlot:name:)`** — creates a new `StepSequenceTrack`:
- `id = UUID()`
- `name = name ?? "\(type.label) \(slotIndex + 1)"`
- `trackType = type`
- `voicing = Voicing.defaults(forType: type)` — from track-destinations plan Task 2b
- `patterns = TrackPatternBank.default(for:generatorPool:clipPool:)`
- Appends to `tracks` array; writes the new ID into `trackSlots[slotIndex]`
- Returns the new ID

**`changeTrackType(atSlot:newType:)`** — destroys + recreates:
- Captures the old track's name (preserve it if possible)
- Calls `removeTrack(atSlot:)` then `createTrack(type: newType, atSlot: slotIndex, name: oldName)`
- Iterates all phrases and removes `trackPatternIndexes` entries for the old track ID (the new track has a fresh ID; users re-reference it explicitly per-phrase)

**Legacy migration (decoder):**

- If JSON has `trackSlots`, use it (and assert invariant; fall back to rebuilt packed layout on violation).
- If no `trackSlots` key: build a packed mapping — `trackSlots = (0..<64).map { i in i < tracks.count ? tracks[i].id : nil }`.

**Tests:**

1. `firstEmptySlot` on an empty document = 0; after `createTrack` at slot 0, firstEmptySlot = 1.
2. `createTrack(type: .drumRack, atSlot: 5)`: `tracks` count grows by 1; `trackSlots[5]` = new ID; other slots unchanged.
3. `createTrack(..., atSlot: 5)` a second time at the same occupied slot returns nil and doesn't mutate.
4. `removeTrack(atSlot:)` on an empty slot is a no-op.
5. `removeTrack(atSlot:)` on an occupied slot clears the slot AND removes from `tracks`. `selectedTrackID` normalised.
6. `moveTrack(fromSlot: 2, toSlot: 5)` where slot 5 is empty: slot 2 becomes empty, slot 5 holds the track.
7. `moveTrack(fromSlot: 2, toSlot: 5)` where slot 5 is occupied: swap (both slots still populated, tracks swapped).
8. `duplicateTrack(fromSlot: 0, toSlot: 1)` where slot 1 empty: new track at slot 1 with same params, fresh ID, " Copy" on name.
9. `duplicateTrack(fromSlot: 0, toSlot: 1)` where slot 1 occupied: returns nil; no mutation.
10. `changeTrackType(atSlot: 0, newType: .drumRack)`: slot 0 now holds a drum track; old track's ID no longer in `tracks`; any phrase's `trackPatternIndexes` entry for the old ID is gone.
11. Legacy decode: a doc without `trackSlots` decodes with tracks packed into leading slots.
12. Invariant tests: `trackSlots.count == 64` after every mutation; every non-nil slot references a present track.

- [ ] Tests (12 cases)
- [ ] Implement fields + mutations + normalisation
- [ ] Green
- [ ] Commit: `feat(document): trackSlots fixed 64-slot grid + slot-aware mutations`

---

## Task 6: `TracksMatrixView` — 8×8 grid of populated + empty cells

**Scope:** Fixed 8-column grid, exactly 64 cells. For each slot index, render either a `TrackCard` (if populated) or an `EmptyTrackCell` (if nil). Clicking populated navigates to the track's detail; clicking empty opens `CreateTrackSheet` for that slot.

**Files:**
- Create: `Sources/UI/TracksMatrixView.swift`
- Modify: `Sources/UI/ContentView.swift` — route `.tracks` to this view
- Create: `Tests/SequencerAITests/UI/TracksMatrixViewTests.swift`

**View shape:**

```swift
struct TracksMatrixView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection
    @State private var createSlotIndex: Int? = nil
    @State private var confirmDeleteSlot: Int? = nil
    @State private var changeTypeSlot: Int? = nil

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: TracksLayout.columnCount
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tracks")
                .font(.largeTitle)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(0..<TracksLayout.slotCount, id: \.self) { slotIndex in
                    if let track = document.model.track(atSlot: slotIndex) {
                        TrackCard(
                            track: track,
                            isSelected: track.id == document.model.selectedTrackID,
                            onTap: {
                                document.model.selectTrack(id: track.id)
                                section = .track
                            },
                            onDuplicate: {
                                if let empty = document.model.firstEmptySlot {
                                    _ = document.model.duplicateTrack(fromSlot: slotIndex, toSlot: empty)
                                }
                            },
                            onChangeType: {
                                changeTypeSlot = slotIndex
                            },
                            onDelete: {
                                confirmDeleteSlot = slotIndex
                            }
                        )
                        .aspectRatio(1.0, contentMode: .fit)
                    } else {
                        EmptyTrackCell(slotIndex: slotIndex) {
                            createSlotIndex = slotIndex
                        }
                        .aspectRatio(1.0, contentMode: .fit)
                    }
                }
            }
            .padding()
        }
        .sheet(item: Binding(
            get: { createSlotIndex.map { SlotBox(index: $0) } },
            set: { createSlotIndex = $0?.index }
        )) { box in
            CreateTrackSheet(
                isPresented: .init(
                    get: { createSlotIndex != nil },
                    set: { if !$0 { createSlotIndex = nil } }
                ),
                slotIndex: box.index
            ) { type in
                if let newID = document.model.createTrack(type: type, atSlot: box.index) {
                    document.model.selectTrack(id: newID)
                    section = .track
                }
            }
        }
        .sheet(item: Binding(
            get: { changeTypeSlot.map { SlotBox(index: $0) } },
            set: { changeTypeSlot = $0?.index }
        )) { box in
            CreateTrackSheet(
                isPresented: .init(
                    get: { changeTypeSlot != nil },
                    set: { if !$0 { changeTypeSlot = nil } }
                ),
                slotIndex: box.index,
                title: "Change Type for Slot \(box.index + 1)"
            ) { type in
                document.model.changeTrackType(atSlot: box.index, newType: type)
            }
        }
        .confirmationDialog(
            "Delete track?",
            isPresented: .init(
                get: { confirmDeleteSlot != nil },
                set: { if !$0 { confirmDeleteSlot = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let slot = confirmDeleteSlot {
                    document.model.removeTrack(atSlot: slot)
                    confirmDeleteSlot = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmDeleteSlot = nil }
        }
        .accessibilityIdentifier("tracks-matrix")
    }
}

private struct SlotBox: Identifiable { let index: Int; var id: Int { index } }
```

Note: `CreateTrackSheet` gains an optional `title` parameter so the same sheet handles both "Create in slot N" and "Change type of slot N" flows.

**Tests:**

1. Renders 64 cells (count children of the grid in state inspection).
2. For a doc with tracks at slots 0, 3, 7: those slots render `TrackCard`; the other 61 render `EmptyTrackCell`.
3. Tapping a populated card selects that track and sets `section = .track`.
4. Tapping an empty cell at slot 5 sets `createSlotIndex = 5` (sheet opens for that slot).
5. Confirming the sheet with `.instrument` calls `document.model.createTrack(type: .instrument, atSlot: 5)`; the slot becomes populated; selection moves to the new track.
6. Context-menu Change Type... opens the same sheet with the change-type code path; picking a type calls `changeTrackType(atSlot:newType:)`.
7. Context-menu Delete opens confirmation; confirm calls `removeTrack(atSlot:)`; slot becomes empty.
8. `.accessibilityIdentifier("tracks-matrix")` present.
9. Empty document still renders all 64 empty cells (no "no tracks yet" special-case; the grid IS the empty state).

- [ ] Tests
- [ ] Implement
- [ ] Wire `.tracks` routing in ContentView
- [ ] Green
- [ ] Commit: `feat(ui): TracksMatrixView 8x8 grid with populated + empty slot handling`

---

## Task 7: "Move to slot…" reorder

**Scope:** Reorder via a context-menu "Move to slot…" picker on populated cells. Opens a small modal showing slot indices 1–64 with populated ones marked; tapping an empty slot moves the track there; tapping an occupied slot swaps. Simpler and more reliable than drag-drop in `LazyVGrid`.

**Files:**
- Create: `Sources/UI/MoveToSlotSheet.swift`
- Modify: `Sources/UI/TrackCard.swift` — add "Move to slot…" context-menu item
- Modify: `Sources/UI/TracksMatrixView.swift` — host the sheet

**Behaviour:**

- "Move to slot…" opens `MoveToSlotSheet` presenting a mini 8×8 grid of slot numbers.
- Populated slots render as a filled button with that slot's track-type glyph (click = swap).
- Empty slots render hollow with just the slot number (click = move).
- The track's current slot is visually marked as "here" and is non-interactive.

**Tests:**

1. Open sheet → 64 buttons visible; 1 marked "here".
2. Tap empty slot 10 for a track at slot 2 → calls `moveTrack(fromSlot: 2, toSlot: 10)`; slot 2 empty, slot 10 holds the track.
3. Tap populated slot 5 for a track at slot 2 → calls `moveTrack(fromSlot: 2, toSlot: 5)` which swaps.
4. Tap the "here" cell → no-op.

- [ ] Tests
- [ ] Implement MoveToSlotSheet
- [ ] Wire context menu
- [ ] Green
- [ ] Commit: `feat(ui): move-to-slot picker for track reorder`

---

## Task 8: Snapshot / UI test coverage

**Scope:** Once the `qa-infrastructure` plan has shipped `swift-snapshot-testing`, add snapshot tests for `TracksMatrixView` in its common states: empty / 3 tracks / 3 tracks with one selected / 3 tracks with one muted. If `qa-infrastructure` hasn't landed yet when this plan executes, skip (leave the test file skeleton with `XCTSkip` calls and a TODO) — this task becomes a no-op until snapshot infra exists.

Also add the `section-tracks` and `track-card-*` identifiers to the screens-tour test in `qa-infrastructure`'s `ScreensTourTests` so the matrix gets a screenshot in `docs/screenshots/`.

**Files:**
- Create: `Tests/SequencerAITests/Snapshots/TracksMatrixSnapshotTests.swift` (skeleton with skips if snapshot infra absent)
- Modify (if exists): `Tests/SequencerAIScreensUITests/ScreensTourTests.swift` — add a `test_screen_tracks` that navigates to `.tracks` via the `section-tracks` identifier and captures

**Tests:**

1. Snapshot baseline files commit alongside the test file.
2. Running `scripts/screenshot-all.sh` (from qa-infrastructure) produces `docs/screenshots/tracks-matrix.png`.

- [ ] Test skeletons + skips if needed
- [ ] Implement when qa-infra is ready
- [ ] Commit: `test(ui): TracksMatrixView snapshot coverage + screens-tour entry`

---

## Task 9: Wiki update

**Scope:** `wiki/pages/tracks-matrix.md` short page describing the nav, the card shape, and the add/reorder/delete flows. Update `wiki/pages/project-layout.md` for the new files.

**Files:**
- Create: `wiki/pages/tracks-matrix.md`
- Modify: `wiki/pages/project-layout.md`

- [ ] Wiki page
- [ ] project-layout updated
- [ ] Commit: `docs(wiki): tracks-matrix page + project-layout update`

---

## Task 10: Tag + mark completed

- [ ] Replace every `- [ ]` in this file with `- [x]` for completed steps
- [ ] Add a `Status:` line after `Parent spec` in this file's header, following the placeholder-token pattern
- [ ] Commit: `docs(plan): mark tracks-matrix completed`
- [ ] Tag: `git tag -a v0.0.7-tracks-matrix -m "Tracks matrix view complete: WorkspaceSection.tracks, TracksMatrixView, TrackCard, AddTrackSheet, reorder / delete / duplicate, selectedTrackID invariant enforced"`

---

## Goal-to-task traceability (self-review)

| Goal / architectural claim | Task |
|---|---|
| `WorkspaceSection.tracks` case + nav button | Task 1 |
| `selectedTrackID` invariant enforced (closes codex review-queue item) | Task 2 |
| Minimal `TrackCard` (type glyph + name only, nav-focused) | Task 3 |
| `EmptyTrackCell` + `CreateTrackSheet` (one-tap type-picker) | Task 4 |
| `trackSlots` fixed 64-slot grid + slot-aware mutations + change-type | Task 5 |
| `TracksMatrixView` 8×8 grid of populated + empty cells | Task 6 |
| "Move to slot…" reorder | Task 7 |
| Snapshot + screens-tour coverage (when qa-infra lands) | Task 8 |
| Wiki | Task 9 |
| Tag | Task 10 |

## Open questions resolved for this plan

- **Section naming collision:** `.track` (singular, the existing detail-view case) vs `.tracks` (new matrix case). Keep both. Nav buttons in the chrome: ["Song", "Phrase", "Tracks", "Track", "Mixer", "Perform"] — "Tracks" takes you to the matrix; "Track" takes you to the selected track's detail.
- **64-slot grid layout:** fixed 8×8. Cells are square (1:1 aspect ratio). Grid uses `LazyVGrid` with 8 flexible columns so it scales with window width but keeps the aspect.
- **Empty-state:** no special empty-state. A fresh document renders 64 empty cells; the user taps one to create. This is the one-and-only track-creation flow in the Tracks view.
- **Card minimalism:** the card shows only type glyph + name. Destination pills, pattern previews, mute indicators all live in the Track detail view. The matrix is nav; the detail is edit.
- **Change type is destructive:** the data-model spec says `TrackType` is immutable. The UX "Change Type…" action does a destroy + recreate in the same slot under the hood. Phrase references to the old track ID are cleaned up during the change. The name is preserved where possible.
- **Reorder via picker, not drag:** `LazyVGrid` drag-drop across cells is finicky on macOS; a "Move to slot…" picker is reliable and keyboard-accessible. Drag-drop can land as polish later.
- **Selection mirror to Phrase view:** `selectedTrackID` is shared; Phrase view reads the same ID so highlights propagate for free.
- **`selectedTrackID` invariant:** Task 2's concern. Init + every mutation that touches `tracks` or `trackSlots` runs `normaliseSelection`. Closes codex's review-queue item `important-selected-track-id-invariant.md`; critique file deleted in the Task 2 commit.
- **Slot index width:** 0..63 (internal), 1..64 (displayed). Code uses 0-based; UI labels use 1-based where labels are shown. Currently no visible labels per slot — deferred until the 8×8 grid feels unlabelled-sparse.
- **Slot count upper bound:** `TracksLayout.slotCount = 64`. Fixed. Going beyond 64 would need either a multi-bank UI (MPC-style pages) or an expanded single grid; both are future plans.
