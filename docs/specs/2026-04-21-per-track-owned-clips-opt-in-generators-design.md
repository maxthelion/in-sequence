# Per-Track Owned Clips + Opt-In Attached Generators

**Date:** 2026-04-21
**Status:** Design — not yet implemented
**Relates to:** `docs/specs/2026-04-20-drum-track-mvp-design.md` (drum-kit creation path), `wiki/pages/drum-track-mvp.md`, `wiki/pages/tracks-matrix.md`

## Goal

Change the default-source model so every track starts with its own clip in the pool, and a generator is something the user explicitly attaches to a track later. Today every new track — single or drum-kit — is pre-wired to the first compatible `GeneratorPoolEntry`, so a four-part 808 kit plays four drum voices through a single shared generator. That conflates "what the preset sounds like" with "which generative engine drives it," and makes generators feel like a default piece of furniture rather than an opt-in engine.

**Verified by:** Creating a new project; adding an 808 drum kit; observing four clips appended to the clip pool (one per part) seeded with the preset's `seedPattern`s, and `attachedGeneratorID == nil` on all four drum-part banks. Adding a single mono-melodic track; observing a fresh template clip appended to the pool and no generator in the pool. Pressing "Add Generator" on a track; observing a new `GeneratorPoolEntry` appended to the pool, the bank's `attachedGeneratorID` populated, and all 16 slots playing the generator. Bypassing one slot; observing that slot play its clip while the other 15 stay on the generator. Pressing "Remove"; observing the generator stays in the pool but the bank detaches and slots revert to clip mode.

## Non-goals

- Retroactive migration of existing documents. Documents saved under the old "shared generator" default continue to load and play unchanged; `attachedGeneratorID` is absent and decodes as `nil`, and existing slot-level `sourceRef.generatorID` references resolve directly. No automatic hoisting of old shared references into `attachedGeneratorID`.
- Pool pruning / garbage collection of orphaned pool entries. Removing a generator from a track does not delete it from `generatorPool`; the user may re-attach it or edit it from a future pool manager. Same policy applies to clips.
- Reconciling `StepSequenceTrack.stepPattern` with per-part clip content. Drum-kit parts continue to carry `stepPattern = member.seedPattern` as they do today; the clip now duplicates that data. Unifying the two storage sites is its own cleanup and out of scope here.
- A pool-management UI for inspecting / renaming / deleting pool entries en masse.
- Multi-generator-per-track attachments. A track has at most one attached generator. Bypass is the per-slot escape hatch; layering multiple generators is not part of this design.

## Architecture

Three layers of change — data model, document construction, and UI surface. Backward compat is maintained by additive decoding.

### 1. Data model

**`TrackPatternBank` gains `attachedGeneratorID: UUID?`.** This is the single source of truth for "the track's attached generator." Encoded unconditionally; decoded with `decodeIfPresent` defaulting to `nil`. No other fields change on `TrackPatternBank`.

**`SourceRef` keeps its current shape** (`mode: TrackSourceMode`, `generatorID: UUID?`, `clipID: UUID?`) but the semantics of the unused field tightens: a slot can carry both a `generatorID` and a `clipID` at once, with `mode` picking which plays. The existing `.generator(_:)` / `.clip(_:)` factories are augmented so that mode changes preserve the other field rather than zeroing it — this is what makes bypass/remove round-trip cleanly. Call sites that previously relied on the factories zeroing the other field are audited and updated.

**No new field is added for "the track's owned clip".** The per-track clip is just an entry in `Project.clipPool`, created at track-creation time with a fresh UUID. After creation it has no privileged status — a user can re-point a slot at any compatible clip via the clip picker, and the original per-part clip is then just a pool entry like any other.

### 2. Document construction

**`TrackPatternBank.default(for:initialClipID:)`** replaces the current `default(for:generatorPool:clipPool:)`. The new signature takes the clip ID that the track's 16 slots should default to. `attachedGeneratorID` is always `nil`. All 16 slots are `.clip(initialClipID)` with `generatorID == nil`. The old signature's pool parameters are removed from this constructor; pools are no longer consulted at default-bank time.

**`Project.appendTrack(trackType:)`** builds the track, then creates a per-track clip:

1. Pick a matching template from `ClipPoolEntry.defaultPool` by `trackType`.
2. Copy it with a fresh UUID and an identifying name (e.g., `"\(track.name) clip"`).
3. Append to `clipPool`.
4. Build the bank via `TrackPatternBank.default(for: track, initialClipID: newClip.id)`.

No entries added to `generatorPool`.

**`Project.addDrumKit(_:)`** builds one clip per preset member:

1. For each `preset.members` entry:
   - Construct a `ClipPoolEntry` with `trackType: .monoMelodic`, `name: member.trackName`, `content: .stepSequence(stepPattern: member.seedPattern, pitches: [DrumKitNoteMap.baselineNote])`, and a fresh UUID.
   - Append to `clipPool`.
2. Build each member's bank via `TrackPatternBank.default(for: track, initialClipID: memberClip.id)`.

No entries added to `generatorPool`. Drum-kit preset behavior is preserved — picking 808 still gives the classic kick/snare/hat/clap pattern — but the data is now structured as four clips the user owns rather than one shared generator.

### 3. Generator attach / remove / bypass

New methods on `Project`, composed with existing pattern-bank mutators:

**`attachNewGenerator(to trackID: UUID) -> GeneratorPoolEntry?`**
- Resolves the track and its bank.
- Picks the matching template from `GeneratorPoolEntry.defaultPool` by the track's `trackType`.
- Copies it with a fresh UUID and identifying name.
- Appends to `generatorPool`.
- Sets `bank.attachedGeneratorID = newEntry.id`.
- For each of the 16 slots, flips `sourceRef.mode = .generator` and sets `sourceRef.generatorID = newEntry.id`; **preserves** the existing `sourceRef.clipID` so remove/bypass has a clip to fall back to.
- Returns the new entry.

**`removeAttachedGenerator(from trackID: UUID)`**
- Resolves the track and its bank.
- Captures `removedID = bank.attachedGeneratorID` (no-op if nil).
- Clears `bank.attachedGeneratorID`.
- For each slot whose `sourceRef.generatorID == removedID`, flips `sourceRef.mode = .clip` but leaves `sourceRef.generatorID` in place. `sourceRef.clipID` is already present (from attach); the slot now plays that clip.
- Does **not** remove the entry from `generatorPool`. Deletion is a separate, deliberate action.

**`setSlotBypassed(_ bypassed: Bool, trackID: UUID, slotIndex: Int)`**
- Resolves the track and its bank. No-op if `bank.attachedGeneratorID == nil`.
- If `bypassed == true`: flip the slot's `sourceRef.mode = .clip`. `generatorID` and `clipID` both stay resident.
- If `bypassed == false`: flip the slot's `sourceRef.mode = .generator`. `generatorID` and `clipID` both stay resident.

`Project+TrackSources.swift` gains these three methods. `Project+Codable.swift` gains `attachedGeneratorID` handling in `TrackPatternBank`'s encode/decode (via `TrackPatternBank`'s own `Codable` conformance, not `Project`'s). `TrackPatternBank.synced(track:generatorPool:clipPool:)` preserves `attachedGeneratorID` through syncing and validates that the attached ID still exists in the pool (clearing it if not).

### 4. UI surface

The current `TrackSourceModePalette` (Generator/Clip pill) no longer fits the model — source "mode" is no longer the primary user-facing concept; the generator is an attached-or-not resource, and the slot-level choice is engaged-or-bypassed. The palette is collapsed into a contextual generator control inside `TrackSourceEditorView`'s Source panel:

- **No generator attached (`attachedGeneratorID == nil`):** a single "Add Generator" button. Pressing it invokes `attachNewGenerator(to:)`. The Source panel below continues to show the clip picker and clip preview driven by the currently-selected slot.
- **Generator attached:** shows the attached generator's name and a "Remove" button. Pressing Remove invokes `removeAttachedGenerator(from:)`. The generator editor panel (`GeneratorParamsEditorView`) becomes visible and edits the attached entry in place. A picker for re-pointing the bank at a different existing pool entry lives inside the generator editor panel (demoted from the Source panel), rendered only when the pool contains more than one compatible entry.

The `TrackPatternSlotPalette` (the 16-slot strip) gains a per-slot bypass affordance, visible only when a generator is attached — a small corner indicator that toggles on click. When bypassed, the slot shows its clip reference visually (distinct from the attached-generator slots).

`TrackSourceModePalette.swift` is deleted. Its `Generator` / `Clip` labels are no longer a user-facing toggle; mode is now a consequence of the contextual control and per-slot bypass.

## Backward compatibility

- Old documents lacking `attachedGeneratorID` on any bank decode fine — the field defaults to `nil`.
- Old documents whose slots carry `sourceRef.mode == .generator, generatorID == <shared pool entry>` continue to play: the dispatch path resolves via `sourceRef.generatorID` independently of `attachedGeneratorID`. The bank will present in UI as "no generator attached" even though slots play through the shared generator — a cosmetic regression for legacy documents that does not affect audio. Users can press Remove-equivalent (there isn't one in this state) by switching individual slots to clip mode via the slot-level interaction, or by opening the file and re-saving after attaching a generator. We accept this; retroactive hoisting is explicitly out of scope.
- `TrackPatternBank.default(for:generatorPool:clipPool:)` has several callers today: `appendTrack` and `setSelectedTrackType` in `Project+Tracks.swift`, the selection defaults in `Project+Selection.swift`, and the codable fallback paths in `Project+Codable.swift` and `Project+Patterns.swift`. All call sites migrate to the new `default(for:initialClipID:)` constructor. For callers that don't already have a clip to point at (notably the codable fallback paths repairing corrupt saves), the migration is: first ensure a compatible clip exists in `clipPool` (reusing `ensureCompatibleClip(for:)`), then pass its id to the new constructor.

## Test plan

Unit tests (new or extended, in `Tests/Document/`):

- **`ProjectAddDrumKitTests`** — `addDrumKit(.kit808)` leaves `generatorPool` unchanged; appends exactly 4 entries to `clipPool` (one per preset member); each appended clip's `content` is `.stepSequence` with the member's `seedPattern` and `[DrumKitNoteMap.baselineNote]` pitches; each member track's bank has `attachedGeneratorID == nil` and all 16 slots `.clip(memberClip.id)`. Parallel tests for `.acousticBasic` and `.techno`.
- **`ProjectAppendTrackTests`** — `appendTrack(.monoMelodic)` appends one clip to `clipPool` with `trackType == .monoMelodic` seeded from `ClipPoolEntry.defaultPool`; bank has `attachedGeneratorID == nil` and slots point at the new clip; `generatorPool` unchanged. Parallel for `.polyMelodic`, `.slice`.
- **`ProjectGeneratorAttachmentTests`** — `attachNewGenerator(to:)` appends one entry to `generatorPool`; sets `attachedGeneratorID`; all 16 slots flip to `.generator` mode with `generatorID` matching; each slot's `clipID` is preserved from before. Pool entry's `trackType` matches track's `trackType`.
- **`ProjectGeneratorRemoveTests`** — `removeAttachedGenerator(from:)` after attach: `attachedGeneratorID == nil`; each slot's mode is `.clip`; each slot's `clipID` still points at the original per-track clip; `generatorPool` still contains the detached entry.
- **`ProjectGeneratorBypassTests`** — `setSlotBypassed(true, slot: 3)` on an attached track: slot 3 `.mode == .clip`; slots 0-2 and 4-15 stay `.generator`. `setSlotBypassed(false, slot: 3)` returns slot 3 to `.generator`. `setSlotBypassed` is a no-op on a track with no generator attached.
- **`TrackPatternBankCodableTests`** — round-trip a `TrackPatternBank` with `attachedGeneratorID` set through JSONEncoder/Decoder; preserves the field. Round-trip one with `attachedGeneratorID == nil`; round-trip JSON missing the field entirely (decode as nil).

UI smoke test (manual, pending a proper UI harness):

- Open a new project; open Source panel on the default track. Expect "Add Generator" button, no generator name shown. Press it — button flips to "Remove" with the new generator's name, slot palette shows 16 engaged slots.
- Click a slot; toggle its bypass corner. Expect the slot to visually differ and play its clip. Toggle back — returns to generator-driven.
- Press Remove. Expect the button to flip back to "Add Generator"; slots return to clip visuals.
- Add an 808 drum kit. Expect four drum-part rows; each with "Add Generator" available and no generator attached.

## Rollout

Single plan, ~6 source files plus tests, no decomposition. One tag at the end.

## Decisions taken

- Source mode is no longer a user-facing toggle. The palette collapses into an attach / remove control plus per-slot bypass.
- Generators are per-track, not per-slot. The existing `sourceRef.generatorID` remains per-slot for playback resolution, but new attachments always populate all 16 slots with the same ID.
- Removing a generator from a track does not delete it from the pool. Deletion is a separate user action (not designed here).
- Drum-kit `seedPattern`s move into per-part `ClipPoolEntry`s, not into generator params. The preset's musical intent is now stored as clip data the user owns.
- All new tracks (drum and non-drum) get per-track clips by default. Single-track creation is not exempted.
- `StepSequenceTrack.stepPattern` remains populated from `member.seedPattern` on drum-kit members. Reconciliation is out of scope.
