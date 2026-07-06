# Plan: Limited Color UI And Track Identity Accent

**Status:** Proposed - 2026-07-06
**Goal:** Move the app toward a near-monochrome working UI where color is used
intentionally: one fixed transport accent, one identity accent for the focused
track or phrase surface, and rare semantic colors for destructive, warning,
recording, or success states.
**Execution checklist:** `docs/roadmap/limited-color-ui/goal.md` is the document
to point an implementation agent at. It adds the worktree requirement, subagent
review process, post-implementation checklist, and screenshot evidence gates.
**Guardrail:** Extends `docs/ux-canon.md` Rule 12, "Color identifies, it never
floods." This plan narrows the color language further: color should not identify
track type, pattern number, or arbitrary control category.

## Product Decisions

- **Transport uses a fixed app accent.** It does not follow the selected track.
  Transport is the machine-level surface, so it should remain visually stable
  while track selection changes.
- **Pattern selection has no per-pattern hue.** Pattern identity is position and
  label (`P1`-`P16`), not a rainbow palette. Inside a track surface, selected and
  occupied pattern slots use that track's accent plus neutral chrome.
- **Track type colors are retired.** Mono, poly, slice, audio input, and drum
  groups are distinguished by icon, label, layout, and available controls, not by
  fixed cyan/violet/green/orange assignments.
- **Phrase perform belongs in the same color system.** Phrase/perform surfaces
  should stop assigning unrelated colors to layer modes and action categories
  unless the color is a true semantic state.

## Target Color Roles

| Role | Meaning | Examples |
|---|---|---|
| `neutral` | Default chrome and text | backgrounds, borders, inactive buttons |
| `transportAccent` | Fixed global transport accent | play/stop, BPM, position, current phrase progress |
| `trackAccent` | Focused track or kit identity | track header, tabs, step cells, waveform, macro arcs |
| `phraseAccent` | Focused phrase/perform identity or fixed phrase accent | phrase matrix, perform selection, global apply |
| `danger` | Destructive or error | delete confirmation, clipping/error |
| `warning` | Armed, recording, pending, caution | record armed, unsaved destructive state |
| `success` | Completed/available only where necessary | capture available, saved/ready state |

Default rule: if a color is not one of these roles, it should be neutral.

## Current Evidence

- `Sources/UI/Track/TrackWorkspaceView.swift` currently computes
  `sourceAccent` from `track.trackType`, assigning cyan to melodic, violet to
  slice, and green to audio input. This is the core shape to remove.
- `Sources/Document/TrackPalette.swift` already provides stable identity colors
  for tracks and groups. The plan should promote this from navigator badges to
  the accent source for focused track surfaces.
- `Sources/UI/Theme/StudioTheme.swift` currently defines a 16-color
  `patternPalette`; that palette conflicts with the decision that pattern
  selection should not have one color per pattern.
- A spot scan on 2026-07-06 found many hardcoded uses of
  `StudioTheme.cyan`, `.violet`, `.amber`, and `.success` in the transport,
  phrase, track, slicer, and track-source UI. The migration should be component
  based, not one screenshot at a time.

## Implementation Phases

### Phase 1 - Tokenize the intent

Add a small color-role layer on top of `StudioTheme`:

- `StudioTheme.transportAccent`
- `StudioTheme.phraseAccent`
- `track.identityAccent` / `TrackPalette.identityColor(...)`
- semantic aliases for `danger`, `warning`, and `success`

Keep the existing raw named colors private to the theme where possible. UI code
should ask for a role, not a hue name.

Acceptance:

- New or updated docs in `docs/ux-canon.md` define the limited-color rule.
- New UI code has an obvious role to use without reaching for raw cyan/violet.

### Phase 2 - Track accent source of truth

Replace track-type accent selection with track identity accent:

- `TrackWorkspaceView`
- `TrackSourceEditorView`
- `SliceTrackWorkspaceView`
- audio-input track surfaces
- drum group matrix and kit-wide tabs
- routing, FX, macros, generator, and source tabs inside track detail

Rules:

- Track detail header, section pills, tab well outline, step cells, waveform,
  rotary arcs, selected layer controls, and value highlights all use the same
  `trackAccent`.
- Track type badges may use the track accent for the badge body, but type does
  not choose the hue.
- Kit/group tracks use the group identity accent. Member parts inherit that
  group accent on kit-wide surfaces unless a later product decision introduces
  explicit per-part identity colors.

Acceptance:

- Opening a cyan track makes the whole track editor cyan-accented.
- Opening an orange track makes the same editor orange-accented.
- A slice track no longer becomes purple just because it is a slice track.
- Audio input no longer becomes green just because it is audio input.

### Phase 3 - Pattern selector de-rainbow

Remove visual dependence on `StudioTheme.patternPalette` in track and phrase
pattern selection surfaces.

Rules:

- Selected pattern: solid current surface accent.
- Occupied pattern: neutral body with accent outline or small accent mark.
- Empty pattern: neutral.
- Pattern number/position carries identity.

Acceptance:

- `P1`-`P16` do not render as sixteen different hues.
- Pattern previews and phrase pattern cells do not introduce a second color
  system inside a track/phrase surface.

### Phase 4 - Slicer and sampler color unification

Sweep slicer-specific components:

- main slicer waveform
- slice boundaries and selected marker
- slice-source modal
- selected-slice sampler card
- step strip and step edit rotaries
- source/sample controls

Rules:

- Waveform fill uses `trackAccent`.
- Slice markers use `trackAccent` plus neutral/brightness/width changes for
  selection, not violet/amber/cyan mixing.
- Sampler waveform, buttons, rotary arcs, and selected values use `trackAccent`.
- True warning/success states remain semantic but should be sparse.

Acceptance:

- A slice track has one coherent accent across waveform, steps, sampler, and
  controls.
- The selected slice view no longer mixes green waveform, blue rotaries, and
  purple buttons.

### Phase 5 - Fixed-accent transport

Give transport one fixed accent role.

Rules:

- Play/stop, BPM, position, phrase progress, and active transport mode use
  `transportAccent`.
- Swing active state uses `transportAccent`, not a separate violet state.
- Note activity uses `transportAccent` or neutral pulse, not amber unless it
  indicates warning/recording.
- Record is neutral when unavailable; warning/record color appears only when
  armed or recording.
- Scene A/B indicators should be neutral or use one fixed transport accent
  unless the screen is explicitly comparing two scene identities.

Acceptance:

- Transport no longer reads as cyan + amber + violet + green in one strip.
- Changing selected track does not repaint transport.

### Phase 6 - Phrase perform and phrase layers

Apply the same limited-color rules to phrase surfaces:

- phrase matrix
- phrase perform cards
- global apply
- layer selector
- phrase launch/scheduling controls

Rules:

- A phrase/perform surface should have one accent role, probably
  `phraseAccent`, unless it is displaying track-specific cells that intentionally
  use each track's identity accent.
- Layer modes should not own separate colors by default. Mute/fill/pattern/etc.
  are modes, not hues.
- Play/queue/capture colors should become neutral plus accent, with semantic
  warning/success reserved for actual state.

Acceptance:

- Phrase perform does not present layer/action categories as a rainbow.
- Track-specific content inside phrase views can still use track identity color
  when the color is saying "this track."

### Phase 7 - Enforcement and visual evidence

Add mechanical checks so the old color language does not return:

- Extend `scripts/diagnostics/ux-canon-lint.sh` or add a focused color-role
  lint for hardcoded `StudioTheme.cyan`, `.violet`, `.amber`, and `.success` in
  track, slicer, phrase, and transport UI files.
- Allow semantic exceptions only with an inline annotation explaining the role.
- Capture the standard visual scenarios before and after:
  - transport
  - mono/poly track detail
  - slice track populated, slice tab, source modal, step edit rotaries
  - audio input track
  - drum kit matrix and kit tabs
  - phrase perform, phrase layers, global apply
  - pattern selector surfaces

Acceptance:

- `scripts/diagnostics/ux-canon-lint.sh` passes.
- QA screenshots show one accent per surface, with no per-pattern hue palette
  and no track-type color scheme.
- Any remaining non-neutral color is either the active surface accent or a
  documented semantic state.

## Non-goals

- No broad layout redesign under this plan.
- No document-format migration is required just to start; derived track identity
  colors are already available.
- No new decorative gradients, tinted panels, or accent washes. This plan keeps
  the existing flat dark UI grammar and reduces color usage.
- No audio-engine or sequencing behavior changes.

## Suggested Build Breakdown

1. Add color roles and update canon/lint.
2. Convert track detail to identity accent.
3. Convert pattern selector away from per-pattern hues.
4. Convert slicer/sampler surfaces.
5. Convert transport to fixed accent.
6. Convert phrase perform/layer surfaces.
7. Run visual scenario coverage and file any residual color-role violations.
