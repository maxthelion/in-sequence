---
status: drafted
stage: spec
updated: 2026-06-11
source_artifacts:
  - docs/roadmap/library-pools/README.md
  - docs/roadmap/intent.md (2026-06-10/11 library entries)
  - docs/roadmap/drum-kits-and-templates/spec.md (asset shapes, merged)
---

# Library Pools — Spec

## Purpose

Replace the placeholder Library page with the two-level asset model the
owner described: a **global library** of assets that exist outside any
project, and a **project pool** — the subset this document has pulled in.
Recordings captured from audio-input tracks become durable library assets
instead of dying with the session.

## Decisions on the README's open questions

1. **Pool semantics: reference, don't copy.** Project pools store stable
   asset IDs referencing the global library (the pattern kit parts already
   use: `AudioSampleLibrary`'s UUIDv5 IDs). Documents stay small; a missing
   asset renders as a clearly-marked missing entry, never a crash. A
   "collect into project bundle" portability pass is future work, recorded
   as an exclusion.
2. **Recordings auto-land.** Every completed audio-input capture writes a
   WAV into the global library under a Recordings category, named
   `<track name> — <bar count> bars — <take N>`. No explicit save step
   (owner attention is precious; deleting is easier than re-recording).
3. **Kit shape:** answered by item 27 — `DrumKit` / `PatternTemplate`
   assets, already merged. The library page lists them; their JSON manifests
   already live beside the sample library.

## Part 1 — Recordings persist (model, no UI)

- New `RecordingLibrary` (pattern: `DrumAssetLibrary`) owning
  `<libraryRoot>/recordings/*.wav` plus a small JSON sidecar per take
  (id, name, capturedAt, barCount, bpm at capture, source track name,
  sample rate/channels).
- On `completeAudioInputCapture`, the engine already materializes PCM
  (`completedLoopPCM`); a completion hook writes it to the library off the
  main thread and tags the runtime with the asset ID. Failure to write is
  traced, never fatal; the in-session loop keeps playing from memory.
- Recordings are usable wherever samples are: selectable as a sample
  destination and as slicer source (they appear in the existing
  `AudioSampleLibrary` browsing surfaces via a `.recordings` category or a
  parallel accessor — prefer extending `AudioSampleCategory` so existing
  pickers get them for free).

## Part 2 — Library page

Two sections, StudioPanel grammar, no placeholder prose (ux-canon rule 3):

- **Global library**: category browser — Breaks, Recordings, Drum Kits,
  Pattern Templates, Step Order Maps, and the per-voice sample categories.
  Each category lists name + compact facts (length/bars/parts as
  applicable); audition on click for audio assets
  (`SamplePlaybackEngine.audition`). Assets show an "in project" indicator
  when pooled.
- **Project pool**: what this document references — pooled assets grouped
  by kind, with remove-from-pool (does not delete the global asset) and
  reveal-in-global. Adding: an "Add to project" affordance on global
  entries.
- `Project` gains `assetPool: [PooledAssetRef]`
  (`{kind, assetID, addedAt}`, Codable, defaults empty for legacy docs).
  Pool membership is what creation flows offer first (drum-kit chooser
  lists pooled kits before global ones).

## Part 3 — Consumption hooks (thin)

- AddSliceTrackSheet: breaks list becomes pool-first (pooled breaks on
  top, then global).
- AddDrumGroupSheet kit chooser: pooled kits first.
- Audio-input track: after capture, the take's library entry is visible in
  Recordings immediately.

## Acceptance criteria

- A capture completed in session N is browsable and auditionable in the
  Library in session N+1 (file + sidecar round-trip).
- Recording WAV write failure leaves the session loop functional and
  traces to the activity log.
- Legacy documents decode with an empty pool; pooled-asset references to
  deleted global assets render as missing entries without crashing.
- Library page has zero placeholder prose; capture rows added for both
  sections and a recordings-populated state.
- Pool add/remove is undoable and does not touch files on disk.

## Exclusions

- No copy-into-document portability pass (recorded as future work).
- No renaming/editing of global assets from the Library page in v1
  (delete + re-record covers the recordings case; kit/template authoring
  is item 27's deferred save-as flow).
- No waveform thumbnails in v1 (compact facts only); thumbnail rendering
  is a follow-up.
