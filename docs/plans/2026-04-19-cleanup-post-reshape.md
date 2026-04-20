# Cleanup Plan — Delete Legacy Bridges

**Goal:** The reshape + destination migrations left the codebase in a hybrid state — new types (`Destination`, `TrackGroup`, 3-case `TrackType`) landed while pre-reshape accessors stayed alive to support tests and UI bindings. In a pre-release deletion-favouring posture, every bridge is a bug. This plan deletes them and lets the compiler surface every reader, migrating each to the flat-destination model. Verified by: `grep -r TrackOutputDestination Sources/ Tests/` returns zero matches; `grep -r 'track\.output\|track\.audioInstrument' Sources/ Tests/` returns zero matches; `GeneratorKind` has only the cases the spec names; `BusRef` is gone; `xcodebuild test` green.

**Architecture:** Pure deletion + migration. No new subsystems, no new types. Driven by compiler-error following: delete the old shape, the compiler lists every reader, migrate each reader to the new shape, repeat. The meta-rule being enforced (see `wiki/pages/code-review-checklist.md` addition in `overnight-bt-extension`): *a reshape plan is not complete until every reader of the prior representation is migrated or deleted.*

**Source findings:** `.claude/state/review-queue/adversarial-2026-04-20-overly-accepting.md` — adversarial review executed under the deletion-favouring lens enumerated the 13-item deletion list this plan executes.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`. Follow-up to `docs/plans/2026-04-19-track-group-reshape.md`.

**Depends on:** `track-group-reshape` completed and tagged ✅ (v0.0.9). No dependency on `characterization` — goldens would be useful but are not required; unit tests + `xcodebuild test` is the verification gate for this plan.

**Deliberately deferred:**

- **Further model simplifications** beyond the bridges the review enumerated. If a new drift class surfaces during execution, log it to `.claude/state/insights/` and add to a follow-up plan rather than expanding scope mid-flight.
- **Phrase / Track UI decomposition.** Scoped to `phrase-workspace-split` (which depends on this plan landing first).
- **Wiki prose sweep beyond the plan docs** — a full wiki audit is a separate small plan.

**Status:** In progress — Tasks 1 through 12 implemented in the working tree and verified with focused `xcodebuild test`; closure commit + tag still pending. Tag target: `v0.0.12-cleanup-post-reshape`.

---

## Deletion list (from the adversarial review)

13 items, ordered so each removal tees up the next. Running `xcodebuild build` after each task is the forcing function — the compiler is the audit.

---

## Task 1: Delete `StepSequenceTrack.output` accessor

**Scope:** Remove the getter/setter pair at `Sources/Document/Project.swift:1014-1054`. The getter silently coerces `.inheritGroup → .none` on every read (destroys inheritance). The setter has no `.inheritGroup` arm (cannot express inheritance). Every UI binding to `track.output` is a latent bug.

**Follow-on:** Compiler surfaces readers — the expected set is `InspectorView.swift:35` Picker, `TrackDestinationEditor.swift:30-39`, `MixerView.swift:40`, plus tests. Migrate each: UI Pickers bind to `$track.destination: Destination` directly, presenting a dedicated `.inheritGroup` affordance where relevant.

- [x] Delete `track.output` getter/setter
- [x] Migrate surfaced UI readers to bind to `track.destination`
- [x] Migrate surfaced test readers to read `track.destination`
- [x] `xcodebuild test` green
- [ ] Commit: `refactor(document): delete StepSequenceTrack.output legacy accessor`

## Task 2: Delete `StepSequenceTrack.audioInstrument` accessor

**Scope:** Remove the getter/setter at `Sources/Document/Project.swift:1090-1103`. The getter's `default: return .builtInSynth` swallows every non-AU destination — MIDI-out, silent, and group-inheriting all report "Built-In Synth." Every UI using it to display an instrument label lies; every setter that writes an AU destination into a non-AU track is destructive.

**Follow-on:** Mixer strip label, Inspector row. Migrate to display a destination-aware label computed inline or via a method on `Destination`.

- [x] Delete the accessor
- [x] Migrate readers
- [x] Green
- [ ] Commit: `refactor(document): delete StepSequenceTrack.audioInstrument legacy accessor`

## Task 3: Delete `TrackOutputDestination` enum

**Scope:** The 4-case parallel enum at `Sources/Document/Project.swift` exists only to feed the (now-deleted) `track.output` accessor, `StepSequenceTrack` init's `output:` param, and `defaultDestination(output:)` helper. With Task 1 done, its remaining consumers are the init param (Task 4) and the helper (also Task 4). Delete the enum alongside them.

**Note:** Bundled with Task 4 — the three pieces must die together for the build to stay green.

## Task 4: Delete `StepSequenceTrack` init `output:` / `audioInstrument:` params + `defaultDestination(output:audioInstrument:trackType:)` helper

**Scope:** Remove the legacy initializer params at `Project.swift:916-918` and the helper at `1116-1136`. Five test files still construct tracks via `output: .midiOut` / `.auInstrument`. Migrate them to pass `destination:` directly.

**Follow-on:** Delete `TrackOutputDestination` (Task 3) in the same commit since its last reader is gone.

- [x] Delete init params + helper + `TrackOutputDestination`
- [x] Migrate 5 test files to `destination:`
- [x] Green
- [ ] Commit: `refactor(document): delete legacy output init params and TrackOutputDestination`

## Task 5: Delete `GeneratorKind.drumKit` and `.templateGenerator`

**Scope:** Spec line 51 retires drum-kit as a first-class kind ("drum parts are individual `monoMelodic` tracks"). Remove both cases from the enum at `Sources/Document/PhraseModel.swift:611-668` and the `templateGenerator` compatibility logic at `715-720`. Also delete the default generator pool entry that instantiates `{ kind: .drumKit, name: "Drum Pattern" }`.

**Follow-on:** Compiler surfaces every switch. Each will need either a deletion of the dead arm or a migration to a retained case.

- [x] Delete the two enum cases
- [x] Delete the default-pool "Drum Pattern" entry
- [x] Fix compiler-surfaced readers
- [x] Green
- [ ] Commit: `refactor(document): remove retired GeneratorKind.drumKit and .templateGenerator`

## Task 6: Delete `DrumKitPreset.Member.defaultGeneratorKindID`

**Scope:** The field at `Project.swift:37, 56-72` is authored into every preset but read by nothing. Delete the field and the preset-entry authorship.

- [x] Delete field
- [x] Green
- [ ] Commit: `refactor(document): delete unused DrumKitPreset.Member.defaultGeneratorKindID`

## Task 7: Delete `BusRef` and `TrackGroup.bus`

**Scope:** `Sources/Document/TrackGroup.swift:5-11, 22, 45, 68`. Pure stub with zero consumers. Carrying it invites future mis-adoption ("oh, we already have bus routing modelled"). Delete until a bus-routing plan introduces it with real consumers.

- [x] Delete type and field
- [x] Green
- [ ] Commit: `refactor(document): delete BusRef stub`

## Task 8: Delete or rename `TrackTypeMigrationTests.swift`

**Scope:** `Tests/SequencerAITests/Document/TrackTypeMigrationTests.swift` — commit `1bc2593` rewrote this file when the legacy decoder went away, so it now tests `TrackType`'s current behaviour under a filename that implies migration. Overly-accepting name for an overly-accepting test.

Decision: **delete.** In the no-legacy posture there is no migration to test. If `TrackType` current-behaviour coverage is thin after deletion, add plain unit tests to an existing `TrackTypeTests.swift` (create if absent).

- [x] Delete file (or rename + prune if current-behaviour coverage is load-bearing)
- [x] Green
- [ ] Commit: `test(document): delete vestigial TrackTypeMigrationTests`

## Task 9: Replace `defaultValue(for:)` default-arm with fatalError

**Scope:** `Sources/Document/PhraseModel.swift:253-268` switches on `id: String` with `default: return .scalar(0)`. New layer IDs silently fill with scalar-0 instead of failing loud. In pre-release posture, loud failure is correct.

Options considered: (a) convert switch to enum, (b) keep string switch + `fatalError("unknown layer id \(id)")`. Option (b) is the minimal change; option (a) is cleaner if `PhraseLayerDefinition` already has a typed identifier. Pick whichever matches existing style.

- [x] Replace default arm
- [x] Green
- [ ] Commit: `refactor(document): loud-fail on unknown phrase layer id`

## Task 10: Convert `try?` decode paths to explicit catch + assertionFailure

**Scope:** Four sites:
- `Sources/Platform/RecentVoicesStore.swift:105-106` (recent-voices history read)
- `Sources/Audio/AUWindowHost.swift:121` (AU state capture)
- `Sources/Engine/EngineController.swift:938` (`NoteProgram` encode)
- `Sources/Engine/Blocks/NoteGenerator.swift:125` (`NoteProgram` decode)

Each swallows corrupt state. Convert to `do { try … } catch { assertionFailure("…: \(error)") }`. Debug builds crash on malformed persisted state; release builds degrade gracefully (the dev posture wants the crash; production-facing paths still tolerate bad data).

- [x] Convert the four sites
- [x] Green
- [ ] Commit: `fix(persistence): loud-fail on decode errors in dev builds`

## Task 11: Minor `default:` arms in UI switches over model enums

**Scope:** Lower-priority lenient arms at `Sources/UI/MixerView.swift:136` (panLabel), `Sources/UI/PhraseWorkspaceView.swift:1216`, `Sources/UI/InspectorView.swift:115`. Each collapses unhandled cases into a visual fallback; under the no-legacy stance, they should exhaust cases.

- [x] Make the three switches exhaustive
- [x] Green
- [ ] Commit: `refactor(ui): exhaustive switches on model enums`

## Task 12: Wiki / plan prose prune

**Scope:** `wiki/pages/track-groups.md` and several plan docs still name `drumKit` as a first-class concept. Sweep references after Task 5.

- [x] Prune
- [ ] Commit: `docs(wiki): remove retired drum-kit references`

## Task 13: Tag + mark completed

- [ ] Replace `- [ ]` with `- [x]` on completed tasks
- [ ] Add `Status:` line after Parent spec
- [ ] Commit: `docs(plan): mark cleanup-post-reshape completed`
- [ ] Tag: `git tag -a v0.0.12-cleanup-post-reshape -m "Delete legacy destination bridges, retired GeneratorKind cases, unused stubs, and lenient decode/switch paths. Codebase is now single-model (flat Destination); no hybrid state remains."`

---

## Goal-to-task traceability

| Deletion target | Task |
|---|---|
| `track.output` accessor | 1 |
| `track.audioInstrument` accessor | 2 |
| `TrackOutputDestination` enum | 3 (bundled) |
| Init `output:` / `audioInstrument:` + helper | 4 |
| `GeneratorKind.drumKit` / `.templateGenerator` | 5 |
| `DrumKitPreset.Member.defaultGeneratorKindID` | 6 |
| `BusRef` + `TrackGroup.bus` | 7 |
| `TrackTypeMigrationTests.swift` | 8 |
| `defaultValue(for:)` default arm | 9 |
| `try?` decode paths (4 sites) | 10 |
| UI switch `default:` arms | 11 |
| Wiki/plan prose | 12 |
| Tag | 13 |

## Discipline

- **Compiler is the audit.** After each deletion, compile before migrating readers. Don't grep for readers first — trust the compiler. If the compiler misses a reader (reflection, string-keyed access), that's a separate finding worth logging.
- **No reinstatement.** If a test fails only because it exercised a deleted path, delete the test, don't restore the path. Tests owning retired contracts are themselves drift.
- **Expected LOC delta:** roughly −200 to −300 LOC across `Sources/Document/`, plus net reduction in `Sources/UI/` and `Tests/`. New case additions (e.g. `Destination.sample` from the sample-pool plan) will now be a single-file switch migration, not an N-site bridge-keeper.

## Open questions

- **Task ordering:** Task 1 ships first because its bug (silent `.inheritGroup` destruction in InspectorView) is the most user-visible. Could be reordered if a different finding is more painful in practice.
- **SwiftUI PickerStyle migration for `track.destination`:** binding a Picker directly to `Destination` needs a tag strategy. Probably worth a small `DestinationPicker` component if three call sites need it; otherwise inline.
