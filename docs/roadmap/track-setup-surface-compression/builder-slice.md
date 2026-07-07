# Compact Setup Header And Clip Controls

- feature id: `track-setup-surface-compression`
- status: PM handoff ready for build-loop promotion when capacity opens
- source cluster: bug-intake `G7`, plus
  `docs/bugs/20260706-113305-move-lane-length-layer-chooser-randomize`
- primary capture: `18-track-detail-steps-clip.png` from
  `in-sequence/qa-surface-coverage` at `9c1744ba`

## Builder Goal

Make the track setup surface feel like one compact instrument panel rather than
a stack of labeled boxes. Compress the top track/setup area and move clip-local
controls into the clip header so the user can see and adjust the musical object
without scanning through repeated titles, grey explanatory copy, or secondary
control rows.

## Included Work

1. Compact track/setup header
   - Keep track title, pattern identity, fill/normal or fill-preview state,
     paging, and perform/config affordances in a dense header treatment where
     the existing workflow needs them.
   - Remove redundant section titles when the selected tab or surrounding
     header already names the content.
   - Preserve the common compressed-header grammar across normal, slicer, kit,
     and audio detail surfaces where this slice touches those headers.

2. Clip header control placement
   - Put lane, length, layer chooser, randomize, and config affordances in or
     adjacent to the clip header instead of leaving them as separate noisy rows.
   - Remove repeated clip pills, mode/status text such as mono/pattern badges
     where it duplicates the header, and grey helper lines that do not change
     the user's next action.
   - When a layer chooser expands, it may use the row below; the collapsed
     state belongs with lane and length.

3. Slicer and sample-player visual economy
   - Keep source/slice tabs legible without extra subtitles or nested title
     boxes.
   - Put waveform-specific controls next to the waveform: start/length/gain
     under or beside the waveform as appropriate, filter controls in the
     adjacent column when present, and slice selection/mapping controls near
     the slice waveform.
   - Avoid extra rounded containers inside already-framed setup panels.

4. Step/slicer row cleanliness
   - Preserve the normal-track step-cell grammar where slicer steps appear:
     number outside the border, simpler inner value bar, and less two-tone
     noise.
   - Keep slice-per-step mapping discoverable enough for review, but do not
     broaden this slice into a new slicer algorithm pass.

## Explicitly Out Of Scope

- AU runtime safety, AU discovery, preset validation, or third-party AU manual
  evidence.
- Mixer/send-channel follow-up or routing graph behavior.
- Scenes IA, Scene Perform management, and phrase-scene navigation.
- Track/Phrase Perform interaction changes beyond preserving existing header
  affordances.
- Broad drum-kit matrix implementation or part sound architecture.
- Transient detection quality from
  `docs/bugs/20260623-131606-i-feel-like-the-transient-finding-and-se` if the
  fix requires improving analysis output. That should split into algorithm
  work with audio/sample evidence.

## Acceptance Checks

- Capture row `18-track-detail-steps-clip` shows lane, length, layer,
  randomize, and config as clip-header controls, with the redundant clip pill,
  duplicate mono/pattern badges, and grey subtext removed.
- Slicer/sample-player captures show waveform-adjacent controls and no repeated
  source/slice/sample-present labels.
- Normal, slicer, kit, and audio detail headers remain visually related where
  this slice touches them.
- The setup workflow still supports choosing source, clip length, layer, fill
  preview/normal state, randomize, and slice-per-step mapping without hiding
  the primary control behind a modal-only path.
- UX canon lint passes for touched UI files, especially no explainer prose on
  working surfaces and no new grey/system-token escapes.
- No audio hard-rule or runtime-safety claim is made from this slice.

## Evidence To Pair Before Promotion

- Updated QA captures for at least:
  - `18-track-detail-steps-clip`
  - populated slicer source/slice rows that show waveform controls
  - sample-player or drum-part sound surface if touched
- Focused UI tests or snapshot/status checks for any command-channel state used
  by new captures.
- `scripts/diagnostics/ux-canon-lint.sh` if `Sources/UI` changes.
- A short builder final that maps each included bug report to either fixed,
  unchanged/out-of-scope, or split.
