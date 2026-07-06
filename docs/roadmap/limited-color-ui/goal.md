# Goal: Limited Color UI And Track Identity Accent

Source plan: `docs/plans/2026-07-06-limited-color-ui.md`.

This is the execution goal for the limited-color UI migration. It exists because
color work is easy to overstate: changing a few obvious accents can leave the
app still reading as cyan + purple + amber + green once real screenshots are
captured. Treat this document as the checklist and verification contract.

## North Star

The app should read as near-monochrome by default: dark ground, neutral chrome,
white/grey text, and one intentional accent per surface.

- Transport has one fixed app accent. It does **not** follow selected track.
- Track detail surfaces use the focused track or kit identity color.
- Pattern selection does **not** use one color per pattern.
- Track type does **not** choose color. Mono/poly/slice/audio/drum are
  distinguished by icon, label, layout, and controls.
- Phrase perform and phrase-layer surfaces follow the same limited-color system.
- Semantic red/amber/green are rare and must mean danger, warning/recording, or
  completed/available state.

## Worktree Requirement

Do implementation in a dedicated worktree, not as dirty production-code edits in
the primary checkout.

Suggested setup:

```sh
git worktree add ../in-sequence-limited-color-ui -b codex/limited-color-ui main
cd ../in-sequence-limited-color-ui
```

If Foreman has already created a build-loop worktree for this goal, use that
instead. Do not mix this work with unrelated UI feedback batches.

## Agent Process

The main agent owns final sign-off and must not accept the implementer's report
at face value.

Use subagents in this shape:

1. **Implementation subagent:** makes the smallest coherent slice of the
   migration in the worktree.
2. **Spec-review subagent:** checks the diff against this document and the
   source plan. It should look for missed hardcoded colors and incorrect color
   roles.
3. **Screenshot-review subagent:** inspects captured screenshots, not just code.
   It should answer: "Does this still look like multiple color languages?"
4. **Adversarial reviewer:** assumes the work is overstated and searches for
   remaining cyan/violet/amber/green leaks, especially in less-travelled tabs.

Do not mark the goal complete until the main agent has read the reviewer
findings and personally walked the checklist below.

## Implementation Checklist

### 1. Color roles and canon

- [ ] Add explicit color roles for `transportAccent`, `phraseAccent`,
      `trackAccent`, `neutral`, `danger`, `warning`, and `success`.
- [ ] Update `docs/ux-canon.md` so Rule 12 includes the limited-color rule:
      color should not identify track type, pattern number, layer mode, or
      arbitrary control category.
- [ ] Add or extend a lint so hardcoded `StudioTheme.cyan`, `.violet`,
      `.amber`, and `.success` in transport, phrase, track, slicer, and
      track-source UI require either replacement with a role or an inline
      semantic-role justification.
- [ ] Verify the lint is specific enough that future agents know what to fix,
      not just that "color bad" happened.

### 2. Track identity accent

- [ ] Replace `TrackWorkspaceView.sourceAccent` track-type logic with a track or
      group identity accent from `TrackPalette`.
- [ ] Ensure mono/poly, slice, audio input, and drum group track detail surfaces
      all receive their accent from the focused track/kit identity.
- [ ] Ensure track headers, section pills, tab wells, step cells, layer controls,
      macro arcs, FX/routing controls, selected values, and waveform fills use
      that same track accent.
- [ ] Ensure track type badges may use the track accent, but never choose the
      accent.
- [ ] Ensure drum-kit-wide surfaces use the kit/group identity accent. If part
      cells need track identity, color must mean "this part/track", not "this
      kind of thing."

### 3. Pattern selection de-rainbow

- [ ] Remove visual dependence on `StudioTheme.patternPalette` for pattern
      selection.
- [ ] Selected pattern slots use the current surface accent.
- [ ] Occupied pattern slots use neutral chrome plus accent outline/mark.
- [ ] Empty pattern slots are neutral.
- [ ] Phrase pattern cells and previews do not reintroduce one hue per pattern.

### 4. Slicer and sampler sweep

- [ ] Main slicer waveform fill uses `trackAccent`.
- [ ] Slice boundaries and selected markers use `trackAccent` plus neutral
      stroke/brightness/width differences, not cyan/violet/amber mixing.
- [ ] Slice-source modal uses the same track accent.
- [ ] Selected-slice sampler waveform, buttons, rotaries, values, and step edit
      controls use the same track accent.
- [ ] Remaining amber/green/red in slicer code is either removed or justified as
      true warning/success/danger.

### 5. Fixed-accent transport

- [ ] Play/stop, BPM, position, phrase progress, and active transport mode use
      the fixed `transportAccent`.
- [ ] Swing active state uses `transportAccent`, not violet.
- [ ] Note activity uses `transportAccent` or neutral pulse, not amber unless it
      indicates warning/recording.
- [ ] Record is neutral when unavailable; warning/record color appears only when
      armed or recording.
- [ ] Scene A/B indicators are neutral or use the fixed transport accent unless
      the current screen is explicitly comparing two scene identities.
- [ ] Changing selected track does not repaint transport.

### 6. Phrase perform and phrase layers

- [ ] Phrase perform cards do not assign a different color per layer/action.
- [ ] Layer selector modes do not own separate colors by default.
- [ ] Global Apply, capture, play, queue, and phrase launch controls use neutral
      plus phrase accent, with semantic colors only for actual state.
- [ ] Track-specific cells inside phrase views may use track identity accent
      only when the color is saying "this track."
- [ ] Pattern cells inside phrase views do not use per-pattern colors.

### 7. Mechanical sweep

Run a grep before claiming visual completion:

```sh
rg -n "StudioTheme\.(cyan|violet|amber|success|danger)|patternColor|patternPalette|selectorAccent" Sources/UI
```

For every remaining result:

- [ ] It is a theme definition, not a call site; or
- [ ] It is a true semantic role; or
- [ ] It is replaced with `transportAccent`, `phraseAccent`, `trackAccent`, or
      neutral chrome; or
- [ ] It has an inline justification that a reviewer agrees with.

## Build, Lint, And Test Gates

Run these from the worktree:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS,arch=arm64' build

scripts/diagnostics/ux-canon-lint.sh
```

Checklist:

- [ ] `xcodebuild` reports `BUILD SUCCEEDED`.
- [ ] `ux-canon-lint.sh` passes.
- [ ] Any added color-role lint passes.
- [ ] If Swift tests are affected, run the focused tests and record them here:
      `________________________________`.

## Screenshot Evidence Gate

Capture after implementation. If possible, capture a baseline first in the same
worktree before changes; if no baseline exists, compare against the current app
gallery and inspect the final screenshots directly.

Use the project capture harness:

```sh
PEEKABOO_OUTPUT_DIR="$TMPDIR/in-sequence-captures/qa-$USER" \
  scripts/visual-scenarios/qa-surface-coverage.sh

bug-reporter absorb-captures "$TMPDIR/in-sequence-captures/qa-$USER" \
  --project in-sequence \
  --source qa-surface-coverage
```

Minimum surfaces to inspect:

- [ ] Transport, including swing active and phrase navigation.
- [ ] Tracks navigator with multiple track identity colors.
- [ ] Mono/poly track detail.
- [ ] Slice track populated waveform.
- [ ] Slice track source modal.
- [ ] Slice tab / selected-slice sampler.
- [ ] Slice step edit rotaries.
- [ ] Audio input idle/live/recording/loop-ready states.
- [ ] Drum kit matrix and kit tabs.
- [ ] Drum kit FX/macros/mixer/capture surfaces.
- [ ] Pattern selector surfaces in track and phrase contexts.
- [ ] Phrase perform.
- [ ] Phrase layers: mute, pattern, automation, global apply.
- [ ] Phrase launch/scheduling controls.
- [ ] Mixer/scenes if touched by transport, phrase, or semantic color changes.

For each inspected capture, record:

| Surface | Pass? | Evidence / capture ref | Notes |
|---|---|---|---|
| Transport | [ ] |  |  |
| Tracks navigator | [ ] |  |  |
| Track detail | [ ] |  |  |
| Slicer | [ ] |  |  |
| Audio input | [ ] |  |  |
| Drum kit | [ ] |  |  |
| Pattern selection | [ ] |  |  |
| Phrase perform/layers | [ ] |  |  |
| Mixer/scenes if touched | [ ] |  |  |

Screenshot review questions:

- [ ] Can I name the one accent for this surface?
- [ ] Are all other colors neutral or true semantic states?
- [ ] Does any track detail still look type-colored?
- [ ] Does any pattern selector still look rainbow-coded?
- [ ] Does transport still show multiple unrelated accent colors?
- [ ] Does phrase perform still read as several mode/action colors?
- [ ] Are there any translucent accent fills or tinted containers violating
      `docs/ux-canon.md` Rule 12?

If any answer fails, the goal is not done. File or fix the issue before final
sign-off.

## Completion Standard

This goal is complete only when all of the following are true:

- [ ] The implementation happened in a dedicated worktree.
- [ ] The source plan's product decisions are implemented.
- [ ] The implementation checklist is complete.
- [ ] Build, UX canon lint, and color-role lint are green.
- [ ] Screenshots were captured and inspected after implementation.
- [ ] At least one independent reviewer inspected the screenshots.
- [ ] Remaining non-neutral color call sites are justified as surface accent or
      semantic state.
- [ ] The final report includes capture refs or local paths for the evidence.

Do **not** complete this goal based on:

- a grep count going down,
- a few obvious surfaces looking better,
- the implementer's claim that the theme now passes through `accent`,
- screenshots that were captured before a fresh build,
- screenshots nobody inspected at full size,
- or a review that only read the diff.

The guardrail is simple: if the captured app still feels colorful in the old
way, the work is not done.
