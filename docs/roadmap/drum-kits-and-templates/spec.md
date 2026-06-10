---
status: drafted
stage: spec
updated: 2026-06-10
source_artifacts:
  - docs/roadmap/intent.md (2026-06-10 kit/template entries)
  - docs/roadmap/library-pools/README.md
  - docs/roadmap/drum-parts-as-group/spec.md
  - docs/roadmap/drum-parts-as-group/feedback/2026-06-06-post-merge-kit-matrix-step-editor-grammar.md
---

# Drum Kits, Pattern Templates, and the Kit Matrix as a Step Editor — Spec

## Purpose

Today the drum-group workflow conflates three things inside one enum:
`DrumKitPreset` hardcodes the member parts, the sounds (indirectly, via
category lookup), and the seed step patterns. The owner's direction splits
these into orthogonal, global concepts:

- a **drum kit** is a collection of sounds keyed by part tag — nothing else;
- a **pattern template** is a collection of clips keyed by part tag,
  applicable to any drum group by tag matching;
- the **kit matrix** becomes a true grouped step editor sharing the
  single-track editor's grammar, with a group-level pattern row — and the
  place where templates are imposed on an existing group.

`DrumKitPreset` is removed.

## Part 1 — Model

### VoiceTag stays the keying concept

Parts keep their `VoiceTag` (string: "kick", "snare", "hat-closed", …).
Tags are the join key between kits, templates, sound pools
(`AudioSampleCategory(voiceTag:)`), and group members. No new tag enum in v1;
the canonical tag list remains `DrumKitNoteMap.table`'s keys.

### DrumKit (new, global library asset)

```swift
struct DrumKit: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    /// Ordered parts; order seeds member order at group creation.
    var parts: [Part]

    struct Part: Codable, Equatable, Sendable {
        var tag: VoiceTag
        var trackName: String          // "Kick", "Snare", …
        var sampleID: UUID?            // AudioSampleLibrary stable ID; nil = first sample in tag's category
    }
}
```

- Kits carry **no patterns** and no destination/routing state.
- `sampleID` references the global `AudioSampleLibrary` (stable UUIDv5 IDs).
  A nil or dangling `sampleID` resolves to
  `library.firstSample(in: AudioSampleCategory(voiceTag:))`, i.e. current
  behavior; a part whose tag has no category and no sample resolves to no
  destination (the existing creation path already tolerates this).

### Per-part sound pools

The "pool of kicks / pool of snares" already exists as
`AudioSampleLibrary.samples(in: .kick)` etc. No new storage. The kit editor
and creation modal browse a part's sound choices from the part tag's
category. (Pool-scoping to the project is library-pools (id 26) territory and
out of scope here.)

### PatternTemplate (new, global library asset)

```swift
struct PatternTemplate: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    /// Step patterns keyed by part tag. 16 steps in v1.
    var patterns: [VoiceTag: [Bool]]
}
```

- Application is **by tag matching**: for each group member whose tag has an
  entry, materialize a fresh `ClipPoolEntry`
  (`.stepSequence(stepPattern:, pitches: [DrumKitNoteMap.baselineNote])`,
  named after the member) into the document's `clipPool` and assign it to the
  target pattern slot. Tags present in the template but absent from the group
  are ignored; members without a template entry are left untouched.
- Templates store plain step patterns, not clip-pool references — templates
  are global, clip pools are per-document. Materialize-on-apply keeps
  documents self-contained.
- v1 templates are on/off patterns. Velocity/chance layers in templates are a
  future extension; the model leaves room (swap `[Bool]` for a richer step
  struct later — Codable keyed container keeps this migratable).

### Storage

Both asset types live in the global library, beside the sample library:

- JSON manifests under the app-support library root
  (`<libraryRoot>/kits/*.json`, `<libraryRoot>/templates/*.json`), loaded by a
  `DrumAssetLibrary` (or two small stores) on the `AudioSampleLibrary.shared`
  pattern.
- **Factory content**: the three `DrumKitPreset` cases are converted into
  three factory kits (808 / Acoustic / Techno: same parts, default sounds)
  and three factory templates (their seed patterns, keyed by tag), compiled
  in and always available. User-created kits/templates persist as JSON.

### DrumKitPreset removal

`DrumKitPreset` is deleted. `DrumGroupPlan.templated(from:)` is replaced by
`DrumGroupPlan.from(kit:)` (+ optional template selection carried separately —
see creation flow). Documents never persisted the preset (plans are consumed
at creation), so **no document migration is needed**. Tests asserting preset
seeding move to factory kit/template fixtures.

`DrumGroupPlan.Member.seedPattern` goes away with it: the plan carries
members (tag, name, sound, routing) and an optional `templateID`; pattern
seeding happens via the template-application path so creation-time and
post-creation application share one implementation.

## Part 2 — Creation flow

`AddDrumGroupSheet` is reordered around **sounds first, patterns second**:

1. **Sounds.** Pick a kit from the global pool (factory + user kits), which
   populates the parts list (tag, name, resolved sample per part). Parts stay
   editable after kit selection: rename, add/remove part, swap a part's sound
   from its tag's category pool. "Blank" remains available as "no kit" —
   start from an empty parts list.
2. **Patterns (optional).** Choose a global pattern template to prepopulate,
   or none. Replaces the current "Prepopulate step patterns" toggle. The
   chooser previews which parts the template will fill (tag intersection).
3. **Routing.** Unchanged: optional shared destination, per-member
   routes-to-shared.

Create materializes: tracks + group (existing path), per-part destinations
from the kit's sounds, and — if a template was chosen — template application
into pattern slot 1 (index 0), exactly as the post-creation path below.

## Part 3 — Kit matrix as a grouped step editor

Reworks `DrumKitMatrixView` per the 2026-06-06 feedback. This supersedes the
drum-parts-as-group v1 exclusions "no inline matrix step editing" and "no
group pattern selector", which that spec marked as future extension
boundaries.

### Step-editor grammar

- Step cells are **full-size, shared components with the single-track step
  editor** — same cell views, beat grouping, and hit targets, not a
  miniature. The matrix is the same editor showing several parts stacked.
- Cells are **editable**: tapping toggles the step in the part's active
  pattern clip, through the same typed `LiveSequencerStore` mutations the
  single-track editor uses. (Render paths must not call
  `exportToProject` — the `assertNoExportDuring` guard applies.)
- **Layer controls above the matrix**: the same step-layer selector the
  single-track editor offers (on/off, velocity, chance, and the other
  existing layers), applied matrix-wide. With velocity selected, every
  part-row renders and edits velocity, etc. Layers a given row cannot
  represent render read-only for that row.
- Per-row `P1` buttons are **removed**. The row header is the part name with
  a small chevron affordance that navigates to the part workspace (navigation
  moves off the cells, which now edit).

### Group-level pattern row

- A **1–16 pattern row across the top** of the matrix, styled like a normal
  track's pattern selector.
- Selecting slot N switches **every member** to pattern slot N and the
  matrix shows that slot's contents across parts. Switching uses the same
  per-track pattern-switch behavior/quantization as today's individual
  switching — the group row is a convenience fan-out, not a new playback
  concept. There is still no persisted group-pattern object.
- The row indicates coherence: when all members share an active slot, that
  slot is shown selected; when they diverge (changed individually elsewhere),
  the row shows a mixed state and the existing amber mismatch banner remains.
  Selecting any slot from the row realigns all members.

### Generator-backed slots

Per the feedback, this needs UI exploration, not a guessed answer. v1 ships
the conservative behavior: a row whose active slot is generator-backed
renders its existing generator badge, read-only cells, and no inline editing.
A prototype under `prototypes/` explores richer treatments before any v2.

### Imposing a template (kit view hook)

The kit matrix toolbar gains **Apply Template…**:

- opens a chooser listing global templates, previewing the tag intersection
  with this group ("fills Kick, Snare, Hat — no Clap entry");
- applies into the **currently selected group pattern slot**;
- if any targeted member's slot is non-empty, a confirm step lists what will
  be overwritten before applying;
- application is one undoable batch mutation.

## Acceptance criteria

Model:

- `DrumKit` and `PatternTemplate` round-trip through Codable; dangling
  `sampleID` falls back to first-in-category; factory kits/templates are
  always present and match the old preset parts/patterns.
- `DrumKitPreset` no longer exists in the codebase.
- Applying a template to a group: matched tags get fresh clip-pool entries in
  the target slot; unmatched members untouched; template tags absent from
  the group ignored; the whole apply is a single undo step.

Creation:

- Kit selection populates parts with resolved sounds; parts remain editable;
  blank mode still creates an empty-parts plan.
- Template selection at creation seeds slot 1 via the same application path
  as the kit-view action (one implementation, verified by a shared test).
- No template selected → empty patterns (current blank behavior).

Kit matrix:

- Matrix step cells reuse the single-track editor's cell components and
  toggle steps in the active pattern; toggles are visible in the part
  workspace and vice versa.
- Layer selector switches the whole matrix between on/off, velocity, chance,
  … and edits write through the same mutations as the single-track editor.
- Group pattern row: selecting slot N switches all members to slot N;
  divergent state renders as mixed + amber banner; selection realigns.
- No per-row `P1` buttons; part-name chevron navigates to the part.
- Generator-backed rows render read-only with a generator badge; tapping
  their cells does nothing.
- No `exportToProject` in matrix render paths (guarded test).

## Edge cases

- Kit with a tag that has no sample category (or empty category): part is
  created with no destination, as today; creation does not block.
- Template apply where a member's target slot holds a generator: that member
  is skipped and listed in the confirm step as "skipped (generator slot)".
- Group with duplicate tags (two "tom-mid" parts): template fills the first
  occurrence only; the confirm step says so.
- Pattern lengths: templates are 16-step in v1; applying to a context
  expecting other lengths follows the existing 16-step clip behavior.
- Deleting a user kit/template that a document used has no document impact
  (materialize-on-apply; documents hold no references to either asset type).

## Exclusions and non-goals

- No persisted group-pattern object (the row fans out to per-part slots).
- No project-pool scoping of kits/templates — that is library-pools (id 26);
  this spec defines the asset shapes it will shelve.
- No velocity/chance data in templates (model leaves room).
- No kit/template management UI on the Library page in v1 beyond what the
  choosers need (full library browsing is id 26). A minimal "save current
  group as kit/template" action is desirable but optional in v1; if cheap,
  add it to the kit matrix toolbar.
- No generator-slot editing in the matrix (prototype first).
- No changes to routing editor, trigger mapping, or phrase/scene grammar.

## Validation and evidence expectations

- Model tests: Codable round-trips, factory content parity with the removed
  presets, fallback resolution, template application (matching, skipping,
  overwrite, undo atomicity), creation/kit-view application sharing one code
  path.
- Store/engine tests: matrix step toggles and layer edits produce the same
  mutations as the single-track editor; `assertNoExportDuring` coverage for
  the matrix; group pattern row fan-out matches N individual switches.
- Visual evidence (QA capture rows to add): matrix in on/off, velocity, and
  chance layers; group pattern row coherent and mixed states; Apply
  Template chooser + confirm; generator read-only row; creation modal
  sounds step and template step.
- The existing `29-kit-matrix`/`30-kit-matrix-mismatch` capture rows must be
  updated for the new layout (full-size cells will change vertical budget —
  parts scrolling must be re-verified).
