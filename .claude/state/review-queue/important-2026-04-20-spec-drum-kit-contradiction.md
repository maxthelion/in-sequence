# Important: Spec contradicts itself about the `drum-kit` generator kind

`docs/specs/2026-04-18-north-star-design.md` has two incompatible statements about whether `drum-kit` exists as a generator kind under the flat-track model:

- §"Vocabulary" (resolved direction — flat-track reshape):

  > Generator kind — a code-defined block type: `mono-generator`, `poly-generator`, `template-generator`, `slice-generator`, `authored-scalar`, `saw-ramp`, `midi-in`. Declared in the block palette; each kind declares which track types it's compatible with. **Note: there is no `drum-kit` kind in the flat-track model** — drum parts are individual `monoMelodic` tracks, each with their own generator.

- §"Components inventory" → "Generator kinds — the actual list" (stale relative to the reshape):

  | Kind | Composition | Compatible track types | Notes |
  |---|---|---|---|
  | ... |
  | `drum-kit` | `[VoiceTag: StepAlgo]` + shared `NoteShape` | `drum` | Per-tag step algos. No PitchAlgo. ... |

Implementation follows Vocabulary: `GeneratorKind` in `Sources/Document/PhraseModel.swift` has `monoGenerator, polyGenerator, sliceGenerator` — no `drumGenerator`, no `drum` track type. This matches the spec's intent.

**Fix:** remove the `drum-kit` row from the "Generator kinds — the actual list" table in §"Components inventory", and remove the `drum` compatibility column wherever it appears (spec-wide, `drum` is not a `TrackType`). The `GeneratorKind.drum` `.drum(stepsByVoice:shape:)` case that appears in `GeneratorParams.swift` is for expressing tag-keyed step patterns on a *mono* track that represents a drum voice, consistent with the flat-track reshape — it is not a dedicated drum-kit kind.

**Severity:** documentation-level; no code change. Worth fixing before a new contributor reads the inventory table and implements `.drum` as a `TrackType`.
