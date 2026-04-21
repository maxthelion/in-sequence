# Remove Song View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete the `SongWorkspaceView` and its sidebar / navigation entry. The spec explicitly says *the song IS the ordered phrase list* — there is no separate song model, and the Phrase workspace already handles phrase-list management (insert / duplicate / remove). The Song view is a placeholder for a phrase-ref model the north-star rejected, and its continued presence is misleading.

**Architecture:** UI-only deletion. Four touchpoints:

1. Delete `Sources/UI/Song/SongWorkspaceView.swift` (and the enclosing `Sources/UI/Song/` directory, which contains only that file).
2. Remove the `.song` case from `WorkspaceSection` and its associated `title` / `systemImage` / `subtitle` branches.
3. Remove the "Song" row from `SidebarView`'s `Arrangement` section.
4. Remove the `case .song: SongWorkspaceView()` branch from `WorkspaceDetailView`.

No document model changes — there was nothing Song-shaped to begin with. `TransportMode.song` is **orthogonal** (it means "play through the phrase list top-to-bottom" as a transport mode, not a UI section) and stays. `LiveWorkspaceView`'s `engineController.transportMode == .song` check stays.

**Tech Stack:** Swift 5.9+, SwiftUI, XCTest. No new dependencies.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` — specifically:
- §"Vocabulary" line 57: *"**Song** — the ordered list `project.phrases: [Phrase]`, played top-to-bottom. Not a separate data structure — there is no 'song' object, no phrase-refs, no repeat-count sugar, no conditional refs."*
- §"The two layers (song + phrase)" line 344: *"The song = the ordered phrase list. Playhead steps top-to-bottom. No phrase-refs, no repeat-count sugar, no conditionals."*

**Environment note:** Xcode 16. `xcodebuild` prefixed with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. After deleting files under `Sources/UI/`, run `xcodegen generate` to remove them from the project.

**Status:** Not started. Tag `v0.0.19-remove-song-view` at completion.

**Depends on:** nothing.

**Deliberately deferred:**

- Updating `wiki/pages/project-layout.md:135` which references `Sources/Song/` (note: different path — wiki refers to a hypothetical domain module, not the UI directory; verify during Task 4 whether this wiki line needs to go away).
- Updating `wiki/pages/sequencerbox-domain-model.md` — this describes an *external reference project*, not sequencer-ai's model, so leave as-is.
- A `PhraseListView` sidebar showing the phrase list. Out of scope — the Phrase workspace already does this inline.
- Anything that touches `TransportMode.song`. Keep as-is.

---

## Pre-flight evidence

Ran before drafting this plan; captured here so the engineer can verify the picture hasn't shifted:

| Check | Result |
|---|---|
| `SongWorkspaceView.swift` is a placeholder | ✓ — 72 lines, hardcoded labels ("A", "A Fill", "B", "Outro"), no document state, comment: *"This is a placeholder shell so the future Song editor has a real home in the main studio surface."* |
| Phrase-list management exists in Phrase workspace | ✓ — `Sources/UI/PhraseWorkspaceView.swift:334` calls `insertPhrase`, `:337` calls `duplicatePhrase`. Project has `appendPhrase`, `insertPhrase(below:)`, `duplicatePhrase(id:)`, `removePhrase(id:)`. |
| No document model references `Song` | ✓ — `grep "Song" Sources/Document/` returns zero. |
| Default `WorkspaceSection` is not `.song` | ✓ — three defaults all land on `.tracks` or `.track`. |
| No tests reference `SongWorkspaceView` or `WorkspaceSection.song` | ✓ — grep returns only `TransportMode.song` usages, which stay. |

---

## File Structure

```
Sources/UI/
  Song/                           # DELETED (entire directory)
    SongWorkspaceView.swift       # DELETED
  WorkspaceSection.swift          # MODIFIED — drop .song case and its branches
  SidebarView.swift               # MODIFIED — drop "Song" arrangement row
  WorkspaceDetailView.swift       # MODIFIED — drop .song dispatch
```

---

## Task 1: Delete `Sources/UI/Song/SongWorkspaceView.swift`

**Files:**
- Delete: `Sources/UI/Song/SongWorkspaceView.swift`
- Delete: `Sources/UI/Song/` (the now-empty directory)

- [ ] **Step 1: Verify nothing else imports SongWorkspaceView**

Grep pattern `SongWorkspaceView` across `Sources/` and `Tests/`. Expected: two matches only — the definition itself (file being deleted) and the `case .song: SongWorkspaceView()` line in `WorkspaceDetailView.swift` (which Task 3 removes). Any third match means a caller we missed.

- [ ] **Step 2: Delete the file and the empty directory**

```bash
git rm Sources/UI/Song/SongWorkspaceView.swift
rmdir Sources/UI/Song
```

- [ ] **Step 3: Regenerate the xcodeproj to drop the file from the project**

```bash
xcodegen generate
```

Expected: writes the project without the deleted file.

- [ ] **Step 4: Build (will fail — `WorkspaceDetailView.swift:23-24` still references the deleted type)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: compile error at `WorkspaceDetailView.swift:24` — "cannot find `SongWorkspaceView` in scope." This is expected; Task 3 fixes it. Do not commit yet.

---

## Task 2: Drop the `.song` case from `WorkspaceSection`

**Files:**
- Modify: `Sources/UI/WorkspaceSection.swift`

- [ ] **Step 1: Remove the `.song` case and its branches**

Replace the full contents of `Sources/UI/WorkspaceSection.swift` with:

```swift
import Foundation

enum WorkspaceSection: String, CaseIterable, Hashable {
    case phrase
    case tracks
    case track
    case mixer
    case live
    case library

    var title: String {
        switch self {
        case .phrase:
            return "Phrase"
        case .tracks:
            return "Tracks"
        case .track:
            return "Track"
        case .mixer:
            return "Mixer"
        case .live:
            return "Live"
        case .library:
            return "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .phrase:
            return "square.split.2x2"
        case .tracks:
            return "square.grid.3x3"
        case .track:
            return "waveform.path"
        case .mixer:
            return "slider.vertical.3"
        case .live:
            return "sparkles"
        case .library:
            return "books.vertical"
        }
    }

    var subtitle: String {
        switch self {
        case .phrase:
            return "macro grid and pipeline graph"
        case .tracks:
            return "track matrix, groups, and creation"
        case .track:
            return "pattern, routing, and voice"
        case .mixer:
            return "levels, pan, and output buses"
        case .live:
            return "live matrix and transport control"
        case .library:
            return "presets, templates, and phrases"
        }
    }
}
```

- [ ] **Step 2: Build (still fails at `WorkspaceDetailView.swift` + `SidebarView.swift`)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: compile errors at the remaining two callsites. Tasks 3 and 4 fix those.

---

## Task 3: Drop the `.song` dispatch from `WorkspaceDetailView`

**Files:**
- Modify: `Sources/UI/WorkspaceDetailView.swift` (around line 23)

- [ ] **Step 1: Locate and remove the Song dispatch case**

Read `Sources/UI/WorkspaceDetailView.swift` to find the `switch section` block. Remove the `case .song: SongWorkspaceView()` branch (two lines, approximately 23–24). No replacement — Swift's exhaustive switch is already satisfied without the case, because `.song` no longer exists as an enum case.

- [ ] **Step 2: Build (still fails at `SidebarView.swift`)**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: compile error at `SidebarView.swift:10` — "type 'WorkspaceSection' has no member 'song'". Task 4 fixes it.

---

## Task 4: Drop the "Song" row from `SidebarView`

**Files:**
- Modify: `Sources/UI/SidebarView.swift` (line 10)

- [ ] **Step 1: Remove the Song arrangement row**

Use Edit to remove this line from `Sources/UI/SidebarView.swift`:

```swift
                globalRow(title: "Song", systemImage: "rectangle.stack", sectionValue: .song)
```

No replacement. The Arrangement section now has two rows: Phrase and Tracks.

- [ ] **Step 2: Build succeeds**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: build succeeds. If any other file still mentions `.song` as a `WorkspaceSection` value, Grep found it earlier and it needs removing too — run `grep -rn "WorkspaceSection\.song\|section:.*\.song" Sources/` and resolve.

- [ ] **Step 3: Full test suite passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: all tests pass. `TransportModeTests.swift:6` asserts `TransportMode.allCases == [.song, .free]` — that's the transport mode enum, still present, still asserting correctly.

- [ ] **Step 4: Commit (single commit for the whole removal)**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat(ui): remove SongWorkspaceView — the song IS the phrase list

Per the north-star spec, there is no separate song model: `project.phrases`
played top-to-bottom IS the song. The placeholder SongWorkspaceView imagined
a phrase-ref / repeat-count model the spec explicitly rejects, and the Phrase
workspace already handles phrase-list management (insert, duplicate, remove).

Deletes:
- Sources/UI/Song/SongWorkspaceView.swift (and the empty Song/ directory)
- WorkspaceSection.song case (+ title/systemImage/subtitle branches)
- SidebarView's "Song" arrangement row
- WorkspaceDetailView's case .song dispatch

Unchanged:
- TransportMode.song — orthogonal (playback mode: song = play phrase list
  top-to-bottom, free = manual phrase selection). Used by LiveWorkspaceView
  and TransportModeTests.

Parent spec: docs/specs/2026-04-18-north-star-design.md §Vocabulary
"Song — the ordered list project.phrases; there is no 'song' object".

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Visual verification + tag

**Files:** none (verification + tag + plan status)

- [ ] **Step 1: Open the app and verify**

```bash
./scripts/open-latest-build.sh
```

- Sidebar → Arrangement section: two rows only (Phrase, Tracks). No "Song" row.
- Click each sidebar row in turn. Nothing crashes; each workspace renders.
- Transport → switch between song mode and free mode (if there's a transport control that exposes this). Verify `TransportMode.song` still works as a transport mode — this confirms Task 4 Step 3 didn't accidentally affect the transport path.

- [ ] **Step 2: Flip plan status + tag**

Replace `**Status:** Not started.` in this plan file with `**Status:** ✅ Completed 2026-04-21. Tag v0.0.19-remove-song-view.`

```bash
git add docs/plans/2026-04-21-remove-song-view.md
git commit -m "docs(plan): mark remove-song-view completed"
git tag -a v0.0.19-remove-song-view -m "Remove Song view (placeholder for rejected phrase-ref model)"
```

- [ ] **Step 3: Log a note to sweep `wiki/pages/project-layout.md:135`**

`wiki/pages/project-layout.md:135` references `Sources/Song/` (the hypothetical domain module path, not the UI `Sources/UI/Song/` we just deleted). Verify whether this line now reads wrong. If so, dispatch the `wiki-maintainer` agent to update that page only.

Create `.claude/state/review-queue/followup-2026-04-21-wiki-song-path.md`:

```markdown
# Follow-up: verify wiki/pages/project-layout.md:135

Line `Sources/Song/ — song model / phrase-refs (Plan 3)` in `project-layout.md`
references a domain module that was never built and, per the current spec
(§Vocabulary), will not be built — there is no separate song data structure.
Consider replacing with a single-line note:

> Song: no separate module — `project.phrases: [Phrase]` IS the song.

Dispatch `wiki-maintainer` if updating.
```

Commit:
```bash
git add .claude/state/review-queue/followup-2026-04-21-wiki-song-path.md
git commit -m "chore(state): flag wiki project-layout Song path follow-up"
```

---

## Self-Review

**Spec coverage:** Each of the four architectural touchpoints (delete file, drop enum case, drop sidebar row, drop detail dispatch) has a corresponding task. Transport-mode distinction called out explicitly so it doesn't accidentally get removed. ✓

**Placeholder scan:** No TBDs. Every step names an exact file and describes the exact change. ✓

**Type consistency:** `WorkspaceSection` case names and sidebar string literals match across tasks. ✓

**Scope check:** Small. ~4 files modified + 1 deleted. One implementation commit. One documentation/tag commit. One follow-up-state commit. ✓

**Risk:** Low. No document model change, no behavioral change to transport or phrase editing. Compile errors between Tasks 1 and 4 are expected and visible; they guide the engineer to the next step rather than hiding incomplete state.
