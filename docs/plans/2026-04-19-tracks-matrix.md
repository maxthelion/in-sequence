# Tracks Matrix View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the app a dedicated Tracks matrix as a nav destination — a grid of track cards, each summarising one track at a glance (name, type badge, destination summary, pattern-slot strip preview, mute state). Clicking a card navigates into that track's detail view. From the matrix the user can add, duplicate, reorder, and delete tracks, with type-aware creation flow. Verified by: navigating to the Tracks section shows all tracks as a grid; clicking a card routes to the Track detail with that track selected; adding a new drum track lands with the per-track-type defaults from `track-destinations`; deleting a track doesn't leave a stale `selectedTrackID` (closes the codex review-queue finding).

**Architecture:** New SwiftUI view `TracksMatrixView` that renders `document.model.tracks` as a responsive grid of `TrackCard` components. `WorkspaceSection` gains a `.tracks` case alongside the existing `.song / .phrase / .track / .mixer / .perform / .library`. The studio chrome's section nav gets a new button. Clicking a card sets `document.model.selectedTrackID` and switches `section = .track`, which routes to the existing single-track detail view. Track-creation uses a sheet picker ("Add track → pick type → confirm"), which calls `document.model.appendTrack(type:)` — the method from the `track-destinations` plan that populates the per-type default `Voicing`. Reorder is drag-and-drop within the grid; delete has a confirmation sheet. The `selectedTrackID` invariant fix (from codex's review-queue) lands as part of this plan's init + deletion code paths, since both naturally touch the invariant.

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
- **Track-group / folder hierarchy.** Flat list for MVP.

---

## File Structure

```
Sources/
  UI/
    TracksMatrixView.swift               # NEW — LazyVGrid of TrackCards, new-track sheet, delete flow
    TrackCard.swift                      # NEW — single-track card component
    AddTrackSheet.swift                  # NEW — type picker + name field + Add button
    WorkspaceSection.swift               # MODIFIED — add .tracks case
    StudioTopBar.swift                   # MODIFIED — new nav button for .tracks
    ContentView.swift                    # MODIFIED — .tracks case in the section switch
  Document/
    SeqAIDocumentModel.swift             # MODIFIED — reorderTracks(fromOffsets:toOffset:); robust selectedTrackID invariant in init + mutations
Tests/
  SequencerAITests/
    Document/
      SeqAIDocumentModelTests.swift      # MODIFIED — selectedTrackID invariant assertions (closes the codex review-queue item)
    UI/
      TrackCardTests.swift
      TracksMatrixViewTests.swift
      AddTrackSheetTests.swift
    Snapshots/                           # coverage lands once qa-infra plan ships snapshot infrastructure
      TracksMatrixSnapshotTests.swift    # deferred implementation; file skeleton only
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

## Task 3: `TrackCard` component

**Scope:** Render one track as a card. No navigation logic — pure presentation + tap callback.

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

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(track.name).font(.headline)
                    Spacer()
                    TrackTypeBadge(type: track.trackType)   // Inst / Drum / Slice
                }
                DestinationPill(voicing: track.voicing)     // "Serum 1 · AU" / "MIDI ch1" / "— (none)"
                PatternSlotStripMini(track: track)          // 16 tiny cells, active slot highlighted
                if track.mix.isMuted {
                    Text("MUTED").font(.caption2).foregroundStyle(.red)
                }
            }
            .padding(12)
            .background(isSelected ? StudioTheme.cyan.opacity(0.25) : StudioTheme.border.opacity(0.1))
            .overlay(isSelected ? RoundedRectangle(cornerRadius: 8).stroke(StudioTheme.cyan, lineWidth: 2) : nil)
        }
        .contextMenu {
            Button("Duplicate", action: onDuplicate)
            Button("Delete", role: .destructive, action: onDelete)
        }
        .accessibilityIdentifier("track-card-\(track.id.uuidString)")
    }
}
```

Subviews (`TrackTypeBadge`, `DestinationPill`, `PatternSlotStripMini`) are small view structs that take minimal params. Their implementation is part of this task.

**Tests:**

1. Renders with the track's name and type label.
2. `.accessibilityIdentifier` present and matches `"track-card-\(track.id.uuidString)"`.
3. Tap calls `onTap` exactly once.
4. Context menu's Duplicate button calls `onDuplicate`.
5. `isSelected = true` adds a visible selection treatment (hard to snapshot without the qa-infra plan — for now verify via state inspection that the selected-variant renders a different background colour).
6. Muted state shows a "MUTED" label.

- [ ] Tests
- [ ] Implement TrackCard + subviews
- [ ] Green
- [ ] Commit: `feat(ui): TrackCard component`

---

## Task 4: `AddTrackSheet` component

**Scope:** Modal sheet for creating a new track. Pick type + name + confirm.

**Files:**
- Create: `Sources/UI/AddTrackSheet.swift`
- Create: `Tests/SequencerAITests/UI/AddTrackSheetTests.swift`

**View shape:**

```swift
struct AddTrackSheet: View {
    @Binding var isPresented: Bool
    @State private var selectedType: TrackType = .instrument
    @State private var name: String = ""
    let onAdd: (TrackType, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Track").font(.title2)
            Picker("Type", selection: $selectedType) {
                ForEach(TrackType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)

            TextField("Name (optional)", text: $name)

            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button("Add") {
                    onAdd(selectedType, name.isEmpty ? defaultName(for: selectedType) : name)
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("add-track-confirm")
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    private func defaultName(for type: TrackType) -> String {
        // "Instrument 3" / "Drum 1" / "Slice 2" — pass existing count in via env later
        type.label
    }
}
```

**Tests:**

1. Picker renders all `TrackType` cases.
2. Pressing Add with a selected type + empty name calls `onAdd(selectedType, defaultName)`.
3. Pressing Add with a typed name uses that name.
4. Cancel sets `isPresented = false` without firing `onAdd`.
5. `.accessibilityIdentifier("add-track-confirm")` present on the Add button.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(ui): AddTrackSheet type picker`

---

## Task 5: `SeqAIDocumentModel` track mutations — reorder + delete + appendTrack(type:)

**Scope:** Make sure the document model has everything the matrix needs to add / reorder / delete tracks cleanly. `appendTrack` may already exist; extend to take a `TrackType` param and use `Voicing.defaults(forType:)` (from `track-destinations` plan Task 2b). Add `reorderTracks(fromOffsets:toOffset:)` and `removeTrack(id:)`.

**Files:**
- Modify: `Sources/Document/SeqAIDocumentModel.swift`
- Modify: `Tests/SequencerAITests/Document/SeqAIDocumentModelTests.swift`

**API:**

```swift
public mutating func appendTrack(type: TrackType, name: String? = nil) -> TrackID
public mutating func removeTrack(id: TrackID)
public mutating func reorderTracks(fromOffsets: IndexSet, toOffset: Int)
public mutating func duplicateTrack(id: TrackID) -> TrackID?
```

All four mutations call `normaliseSelection()` (from Task 2) when they're done.

**`appendTrack(type:name:)`** — creates a new `StepSequenceTrack`:
- `id = UUID()`
- `name = name ?? "\(type.label) \(nextIndex)"` where nextIndex counts existing tracks of that type + 1
- `trackType = type`
- `voicing = Voicing.defaults(forType: type)` — uses the Task 2b helper
- `patterns = TrackPatternBank.default(for: type, generatorPool: document.generatorPool, clipPool: document.clipPool)`
- Default `mix`, default pattern-slot, default output-route metadata
- Appends; returns the new ID

**Tests:**

1. `appendTrack(type: .drumRack)`: returned ID exists; `tracks.last.trackType == .drumRack`; `voicing` has multiple entries (drum defaults).
2. `appendTrack(type: .instrument)`: voicing has one entry `"default": .none`.
3. `removeTrack(id:)` on non-existent ID: no-op, no crash.
4. `removeTrack(id:)` on the selected track: `selectedTrackID` ends up pointing at a surviving track (per the invariant from Task 2).
5. `removeTrack(id:)` on the last track: `tracks.isEmpty`.
6. `reorderTracks(fromOffsets: [0], toOffset: 2)`: moves track 0 to position 2; `selectedTrackID` unchanged.
7. `duplicateTrack(id:)`: produces a new track with the same config except a fresh ID and ` Copy` suffix on the name.

- [ ] Tests
- [ ] Implement mutations (existing `appendTrack()` with no param can become a `appendTrack(type: defaultType)`-calling convenience wrapper; or get removed in favour of the new signature — favour the latter for clarity)
- [ ] Green
- [ ] Commit: `feat(document): track mutations — appendTrack(type:)/removeTrack/reorderTracks/duplicateTrack`

---

## Task 6: `TracksMatrixView` + wiring

**Scope:** The actual matrix. Responsive grid using `LazyVGrid`. Renders one `TrackCard` per track. Tap navigates to `.track` with that track selected. Header has `+` button → opens `AddTrackSheet`. Footer/inspector has reorder affordance.

**Files:**
- Create: `Sources/UI/TracksMatrixView.swift`
- Modify: `Sources/UI/ContentView.swift` — route `.tracks` to this view
- Create: `Tests/SequencerAITests/UI/TracksMatrixViewTests.swift`

**View shape:**

```swift
struct TracksMatrixView: View {
    @Binding var document: SeqAIDocument
    @Binding var section: WorkspaceSection
    @State private var isAddSheetPresented: Bool = false
    @State private var confirmDeleteID: TrackID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tracks").font(.largeTitle)
                Spacer()
                Button {
                    isAddSheetPresented = true
                } label: {
                    Label("Add Track", systemImage: "plus")
                }
                .accessibilityIdentifier("add-track-button")
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 16)], spacing: 16) {
                    ForEach(document.model.tracks, id: \.id) { track in
                        TrackCard(
                            track: track,
                            isSelected: track.id == document.model.selectedTrackID,
                            onTap: {
                                document.model.selectTrack(id: track.id)
                                section = .track
                            },
                            onDuplicate: {
                                _ = document.model.duplicateTrack(id: track.id)
                            },
                            onDelete: {
                                confirmDeleteID = track.id
                            }
                        )
                        .onDrag { NSItemProvider(object: track.id.uuidString as NSString) }
                    }
                }
                .padding()
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AddTrackSheet(isPresented: $isAddSheetPresented) { type, name in
                let newID = document.model.appendTrack(type: type, name: name)
                document.model.selectTrack(id: newID)
            }
        }
        .confirmationDialog(
            "Delete track?",
            isPresented: .init(get: { confirmDeleteID != nil }, set: { if !$0 { confirmDeleteID = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let id = confirmDeleteID {
                    document.model.removeTrack(id: id)
                    confirmDeleteID = nil
                }
            }
            Button("Cancel", role: .cancel) { confirmDeleteID = nil }
        }
        .accessibilityIdentifier("tracks-matrix")
    }
}
```

Reorder via `.onMove` on the underlying ForEach — if the grid approach doesn't support `.onMove`, fall back to drag-drop between grid cells or a dedicated "Edit" mode that switches to a reorderable list. For MVP, ship with context-menu-based "Move Up" / "Move Down" if drag is awkward in `LazyVGrid` (it typically is).

**Tests:**

1. Renders one card per track in `document.model.tracks`.
2. Tapping a card selects that track and sets `section = .track`.
3. Add Track sheet opens on button tap; confirmed name+type creates a track via `appendTrack(type:name:)`.
4. Card context menu's Delete opens confirmation; confirm deletes the track via `removeTrack(id:)`.
5. Card shows selection treatment when that track is selected.
6. Empty document (no tracks) renders "No tracks yet — Add one" empty-state with an embedded Add button.
7. `.accessibilityIdentifier("tracks-matrix")` present on root; `"add-track-button"` on add button.

- [ ] Tests
- [ ] Implement
- [ ] Wire `.tracks` routing in ContentView
- [ ] Green
- [ ] Commit: `feat(ui): TracksMatrixView with add / delete / select flow`

---

## Task 7: Reorder implementation

**Scope:** MVP reorder. Start with context-menu Move Up / Move Down on each card (simplest, reliable); drag-drop as a follow-up.

**Files:**
- Modify: `Sources/UI/TrackCard.swift` — add Move Up / Move Down context-menu items that call a passed-in callback
- Modify: `Sources/UI/TracksMatrixView.swift` — wire the callback through to `document.model.reorderTracks`

**Tests:**

1. Move Up on the second track moves it to position 0.
2. Move Up on the first track is a no-op.
3. Move Down on the last track is a no-op.
4. After reorder, `selectedTrackID` still points at the same track (which is now at a different index).

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(ui): track reorder via context-menu move-up/down`

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
| `TrackCard` component | Task 3 |
| `AddTrackSheet` type picker | Task 4 |
| Document-model mutations with per-type defaults | Task 5 |
| `TracksMatrixView` grid + add/delete/select flow | Task 6 |
| Track reorder UX | Task 7 |
| Snapshot + screens-tour coverage (when qa-infra lands) | Task 8 |
| Wiki | Task 9 |
| Tag | Task 10 |

## Open questions resolved for this plan

- **Section naming collision:** `.track` (singular, the existing detail-view case) vs `.tracks` (new matrix case). Keep both. Nav buttons in the chrome: ["Song", "Phrase", "Tracks", "Track", "Mixer", "Perform"] — "Tracks" takes you to the matrix; "Track" takes you to the selected track's detail. Visually distinguish by icon + subtle label weight. Alternative (not chosen): merge into one `.track` case that shows the matrix when nothing is selected and the detail when one is — rejected because it conflates "pick" and "edit" affordances in one nav slot.
- **Reorder UX:** context-menu Move Up / Move Down in MVP. `LazyVGrid` + drag-drop works on macOS but is finicky with grid-to-grid reordering; worth a dedicated follow-up if the user finds context-menu slow.
- **Empty-state:** when the document has zero tracks, the matrix shows a centred "No tracks yet — Add one" with an embedded Add button (redundant with the header button but improves discoverability).
- **Selection mirror to Phrase view:** the Phrase view already shows per-track rails. Selecting a track in the matrix should also highlight that track's row in the Phrase view. Since `selectedTrackID` is the shared state, this comes for free — the Phrase view just reads the same ID.
- **`selectedTrackID` invariant is Task 2's concern** — it touches init + remove + reorder. Worth getting right once rather than sprinkling validation across call sites.
- **Codex's review-queue item `important-selected-track-id-invariant.md` is closed by Task 2** — delete the critique file in the Task 2 commit.
