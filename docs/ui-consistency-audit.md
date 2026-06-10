# UI Consistency Audit

Date: 2026-06-10
Branch: `fix/ui-consistency-bugs` (audited at the checkpoint after the 14 bug-report fixes)
Scope: `Sources/UI` (110 Swift files)

This audit hunts for the *classes* of problems behind the 2026-06-10 bug
reports — components implemented repeatedly instead of shared, and magic
numbers used where a design-token constant exists (or should exist).

## Executive summary

The design-token system is half-adopted. Corner radii are in good shape
(~381 `StudioMetrics.CornerRadius` uses vs 25 literals, and the literals are
mostly tiny 2–8pt radii with no matching token). Typography and spacing are
not: ~138 raw `.system(size:)` font calls bypass `StudioTypography`, and
`StudioMetrics.Spacing` is used **5 times** against roughly 600 `spacing:`
literals and 134 `.padding(n)` literals.

On the component side, five small-control patterns (circular icon buttons,
chips, steppers, segmented controls, status badges) and four medium patterns
(option-button cards, dashed add-cards, section headers, search bars, grid
cells) are each implemented 3–40 times with small accidental variations —
the same root cause as the macro-menu corner radii and close-button bugs.

## 1. Token bypass — numbers used instead of constants

### 1.1 Typography (worst offender)

`StudioTypography` defines a 16-style scale (10–28pt) with 497 `studioText()`
call sites, but ~138 raw `.system(size:)` calls bypass it:

| Raw size | Count | Existing style it shadows |
|---|---|---|
| 10 | 29 | `.micro` |
| 11 | 26 | `.eyebrow` |
| 12 | 17 | `.label` |
| 9  | 15 | none (below scale) |
| 13 | 13 | `.body` |
| 14 | 9  | `.subtitle` |
| 16 | 8  | none (gap between 15 and 18) |
| 15 | 7  | `.placeholderTitle` |
| 22 | 4  | none — the modal-title size has no token |
| 18/8/20/17 | 10 | mixed |

Recommendations:
- Add missing scale steps: `modalTitle` (22), something for 16, and a 8–9pt
  `nano` for icon glyph sizing (or accept icon font sizes as layout, not type).
- Sweep raw sizes 10–15 onto their existing styles; most are pure bypass.

### 1.2 Spacing (biggest gap between intent and use)

`StudioMetrics.Spacing` (tight 6 / snug 8 / standard 14 / loose 18) is used
**5 times total**. Meanwhile:

- `spacing:` literals: 8×135, 12×113, 10×94, 6×51, 4×43, 14×32, 18×26, 16×25 …
- `.padding(n)` literals: 12×37, 14×31, 10×21, 8×11, 20×10, 16×7, 24×5, 18×5 …

The de-facto scale (4/6/8/10/12/14/16/18/20/24) is wider than the declared
one. Either extend `Spacing` to match reality (add 4, 10, 12, 16, 20, 24) and
sweep, or accept spacing literals as policy and delete the unused constants.
The current half-state is the worst option: the constants imply a system that
isn't actually enforced.

### 1.3 Corner radius (mostly healthy)

381 tokenized uses vs 25 literals. The literals cluster at 4 (×10), 8 (×8),
and 2–6 (×7) — sub-`badge` radii used for tiny controls (stepper buttons,
search fields, mini bars). Add `CornerRadius.mini = 4` (and use `badge` for
the stray 8s) to finish the job.

### 1.4 Opacity

`StudioOpacity` is well-used, but ~150 raw `opacity(0.x)` literals remain.
Clusters: 0.8 (×42), 0.7 (×18), 0.85 (×7), 0.18 (×7), 0.9 (×6). The 0.7–0.9
band is mostly text/glyph dimming, which has no semantic token — consider
`StudioOpacity.dimmedGlyph` / `emphasisFill` names for that band.

### 1.5 Fixed frame sizes

Circular icon buttons repeat 24/28/30/34pt squares ad hoc (28×28 ×10+,
30×30 ×8+, 34×34 ×5+, 24×24 ×6+); knobs hard-code 40pt in two files.
Recommend `StudioMetrics.ControlSize` (small 24, close 28, medium 30,
large 34, knob 40).

### 1.6 Colors

No `Color(red:...)` literals outside `Theme/` — fully healthy.

## 2. Component duplication — small controls

| Pattern | Sites | Variation observed | Recommended shared component |
|---|---|---|---|
| Circular icon button (Image + Circle fill + stroke) | 40+ inline across 13 files, 4 private funcs, 1 shared (`StudioModalCloseButton`) | size 24–34, stroke opacity bare/0.8/0.45, weight semibold/bold | `StudioCircleIconButton(icon:size:accent:)` — make `StudioModalCloseButton` a preset of it |
| Stacked +/- / chevron steppers | `TransportBar.bpmStepButton`, `ClipContentPreview.layerCycleButton` (identical 18×13), `PhraseWorkspaceView.stepButton` (28×30) | two sizes, otherwise same | `StudioStepperButtons(axis:onIncrement:onDecrement:)` |
| Chip / pill button | `ClipContentPreview.chipButton` (+isPlaying, +isEnabled), `ProgressionChordGeneratorEditorView.chipButton` (simpler), ~10 call sites | playing indicator, enabled state | `StudioChipButton` with optional flags |
| Segmented control | custom `StudioSegmentedControl` (TrackWorkspaceView, private!), `TransportModePicker`, 17 native `.pickerStyle(.segmented)` | native pickers don't match theme at all | promote `StudioSegmentedControl` out of the private file; decide native-vs-custom policy |
| Status badge pill | `TrackSourceSlotWellTabBar.badge` (only impl) | — | low priority; extract if reused again |

## 3. Component duplication — medium patterns

| Pattern | Sites | Recommended component |
|---|---|---|
| Option-button card (bold title + muted detail + bordered fill) | `AddDestinationSheet.optionButton`, `CreateTrackSheet.createButton`, `TrackSourceGeneratorSelectionSheet` rows | `StudioOptionButton(title:detail:accent:)` |
| Dashed "add" plus-card | `TracksMatrixView.addTrackCard`, `ScenesWorkspaceView.addSceneCard` (identical), `MixerView.AddBusView`, 2 empty-cell variants | `StudioAddCard(label:accent:minHeight:)`; dash pattern should be one constant ([5,5] vs [4,4] today) |
| Section header (uppercase eyebrow + tracking 0.8 + bg) | `MacroPickerSheet`, `PresetBrowserSheet`, `SingleMacroSlotPickerSheet` (3 near-identical private funcs), plus inline copies | `StudioSectionHeader(title:)` |
| Search bar (magnifyingglass + field + fill) | same 3 picker sheets; PresetBrowser uses `.roundedBorder` style while others use `.plain` | `StudioSearchBar(text:placeholder:)` |
| Grid cell container (selected-accent border + fill) | `PhraseLaunchGrid.phraseCell`, `PerformanceLayerOptionCell`, `sceneCard`, `PhraseMatrixPhraseCell`, track matrix cards, sample cells | `StudioGridCell { content }` handling selection border/fill; cells keep their inner content |

## 4. Remaining chrome / behavior gaps

- **Sheets not yet on StudioModal**: `MixerWorkspaceView.addSendFXSheet`,
  `ScenesWorkspaceView+Perform.scenePerformSlotPickerSheet` (manual ZStack +
  close button), `ScalarCellScrubber` (detent half-sheet, Done button, no
  dark fill), `SlicerWaveformWindow` (large editor window), `AddSliceTrackSheet`.
- **Drag-to-edit sensitivity drift**: MacroKnob 200, AUMacroSlotKnob 220,
  StudioRotaryKnob 180, phrase-cell scalar drag 120 — four constants for one
  gesture. Extract one helper (or at least one shared constant) with a
  documented feel.
- **Empty states**: `StudioPlaceholderTile` is used in ~17 places, but seven
  ad-hoc text-only "No X found" remain (PreferencesView ×3, the picker
  sheets, and four separate copies of the literal string "No AU effects
  found" in mixer views).
- **Explainer text**: ~21 inline instructional sentences remain (worst:
  GeneratorParamsEditorView's 100–140-char modifier explanations,
  TrackSource wells, step-order map editor). Same class as the orange
  fill-preview caption — candidates for tooltips or removal.
- **Toggles**: consistent (`.switch`/`.checkbox` everywhere) — no action.

## 5. Suggested execution order

1. **StudioMetrics.ControlSize + StudioCircleIconButton** — kills the
   biggest inline-duplication class (40+ sites) and the 24/28/30/34 magic
   numbers together.
2. **Typography sweep** — add `modalTitle`/16pt steps, then mechanical
   replacement of raw 10–15pt sizes (~110 of the 138 calls).
3. **Picker-sheet trio dedup** — `StudioSectionHeader` + `StudioSearchBar`
   remove three copies each in the macro/preset pickers.
4. **StudioOptionButton + StudioAddCard** — card-level consistency.
5. **Remaining StudioModal adoptions** (addSendFX, scene perform slot
   picker, scalar scrubber).
6. **Spacing decision** — extend and enforce `Spacing`, or delete it.
   (Largest sweep, lowest visual risk; do last and mechanically.)
7. **Drag sensitivity constant** + empty-state sweep as small follow-ups.

Items 1–5 are bounded component refactors suitable for one build-loop slice
each; 6 is a mechanical sweep best done with a lint rule or script.

## Status update (2026-06-10, branch fix/ui-component-dedup)

Executed:
1. ✅ `StudioMetrics.ControlSize` + `StudioCircleIconButton` (18 inline sites
   converted, 5 private helpers deleted) + `StudioStepperButtons` (BPM stepper
   and layer cycler unified).
2. ✅ Typography: added `heading` (16) and `modalTitle` (22); 17 exact-match
   raw sizes swept onto styles. ~100 remaining raw sizes are genuinely
   off-scale (8/9pt micro-glyphs, odd weights) or icon glyph sizing — left by
   policy.
3. ✅ `StudioSectionHeader` + `StudioSearchBar`; the three picker sheets no
   longer carry private copies, and the preset browser's odd `.roundedBorder`
   field is unified.
4. ✅ `StudioOptionButton` + `StudioAddCard` adopted (destination picker,
   create-track, generator picker, add-track/scene/bus cards; one dash
   pattern).
5. ✅ StudioModal adopted by the last holdouts (send-FX sheets ×3, scene
   perform slot picker, scalar cell scrubber — closing now commits the value).
6. ✅ Spacing scale extended (hairline…page) and all uniform `.padding(n)`
   literals swept onto tokens; `CornerRadius.mini` added and 4/8pt radius
   literals swept. Stack `spacing:` literals remain accepted micro-layout per
   the documented policy in StudioMetrics.
7. ✅ One shared drag sensitivity (`StudioDrag.fullRangeTravel`); ad-hoc
   "No AU effects found" empty states unified on `StudioEmptyListRow`.

Deliberately out of scope: PreferencesView keeps system Form styling (it is a
macOS Settings window); 17 native segmented pickers remain pending a decision
on native-vs-custom segmented control policy.
