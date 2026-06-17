# Resolution: flat UI try-it variant

Status: **pass 3 (color grammar) built for evaluation — not merged**. Merging
awaits your judgment.

## Pass 3 — "color identifies, it never floods" (current)

Verdict on pass 2: translucent accent used as a CONTAINER fill survives
("orange translucent on top of grey… a mess") — scene A/B cards, perform
track cards, and the Track Source editor flooding green. Pass 3 enforces one
color grammar UI-wide, now canonized as **ux-canon rule 12**:

1. Containers (cards, panels, wells, sections) are never tinted — ground or
   the single neutral step, with state/identity in the OUTLINE plus at most
   one small SOLID badge.
2. Small elements (pads, step cells, badges, pills, value chips, segmented
   thumbs) carry state as FULLY SOLID accent fills with dark glyphs/text.
3. Values/numerals may be accent-colored text.
4. Translucent accent fills are banned at every scale (composing accents
   into StudioOpacity fill tokens counts). Hover/pressed = neutral step or
   outline brightening.

### Site-by-site audit

Rulings: **R1** = container → neutral fill + accent outline (± solid badge);
**R2** = small element → fully solid accent + dark glyph/text;
**R1-wash** = value/progress region → neutral wash + solid accent head line.
Lines are post-change positions on `feature/flat-ui-variant`.

#### The three reported areas

| Site | Element kind | Ruling |
| --- | --- | --- |
| Sources/UI/TracksMatrixView.swift:1284 (`cardFill`) | perform/edit track card body | R1 — color branches removed entirely; state in `cardStroke` + solid pattern chip |
| Sources/UI/TracksMatrixView.swift:1432 (`labelBackground`) | runtime trigger surface (HELD/LATCHED) | R1 — neutral body; accent outline + accent state text |
| Sources/UI/TracksMatrixView.swift:1543 (`TrackTypeBadge`) | 30pt type icon badge | R2 solid + dark glyph |
| Sources/UI/TracksMatrixView.swift:929 | group "N tracks" count chip | R2 solid + dark text |
| Sources/UI/TracksMatrixView.swift:978 | placeholder layer icon circle | R2 solid + dark glyph |
| Sources/UI/TracksMatrixView.swift:1043 | MOM/LATCH segmented thumb | R2 solid amber thumb + dark text |
| Sources/UI/TracksMatrixView.swift:1184 | edit-set toggle circle | R1 — neutral fill, amber outline/glyph |
| Sources/UI/TracksMatrixView.swift:1728, 1743 | sample play button / "Use Loop" button | R2 solid violet + dark text |
| Sources/UI/Mixer/ScenesWorkspaceView.swift:195 | scene A/B card (active) | R1 — neutral card, amber outline, solid A/B badge |
| Sources/UI/Mixer/ScenesWorkspaceView.swift:176 | scene card icon badge | R2 solid amber + dark glyph |
| Sources/UI/Mixer/ScenesWorkspaceView.swift:219 (`slotBadge`) | A/B slot badge | R2 solid amber + dark text (the reference "A" chip) |
| Sources/UI/Mixer/ScenesWorkspaceView.swift:336, 386 | insert row icon badge / selected insert row | R2 solid badge; R1 row (cyan outline carries selection) |
| Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift:113 | perform slot header (dominant) | R1 — neutral; amber outline + amber slot label |
| Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift:225 | scene picker icon badge | R2 solid when selected; neutral otherwise |
| Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift:301 | crossfader value track | R2 — solid amber value fill |
| Sources/UI/TrackSource/TrackSourceSlotWellTabBar.swift:159 | SOURCE/MODIFIER/HISTORY selected tab | R1 — neutral tab body; accent outline + underline |
| Sources/UI/TrackSource/TrackSourceSlotWellTabBar.swift:189 | tab state badge (Clip/Gen/Live/N-A) | R2 solid + dark text |
| Sources/UI/TrackSource/TrackSourceSelectedWellBody.swift:34 | selected well body (the green flood) | R1 — neutral body, accent outline (`usesActiveSectionFill` removed) |
| Sources/UI/TrackSource/TrackSourceSourceWell.swift:168 | "Clip"/"Gen"/"Empty" badge | R2 solid + dark text |
| Sources/UI/TrackSource/TrackSourceModifierWell.swift:158 | modifier badge | R2 solid + dark text |
| Sources/UI/TrackSource/TrackSourceEditorView.swift:277 | clip-history toast | R2 solid success + dark text |
| Sources/UI/TrackSource/TrackSourceEditorView.swift:540 | save-armed banner (CLIP panel row) | R1 — neutral; success outline |
| Sources/UI/TrackSource/TrackSourceActionButton.swift:15 | action pill (Add Source / Back / Cancel) | R2 solid + dark text |
| Sources/UI/TrackSource/GeneratorAttachmentControl.swift:67 | "Add Generator" pill | R2 solid + dark text |
| Sources/UI/TrackSource/TrackSourceContainedModifierPicker.swift:188 | picker action tile (title+detail) | R1 — neutral; accent outline |
| Sources/UI/TrackSource/TrackSourceContainedSourcePicker.swift:441 | primary recovery action tile | R1 — neutral; accent outline |
| Sources/UI/TrackSource/TrackPatternSlotPalette.swift:115–186 | P1–P16 slot pads + C/G bypass badge | R2 — selected/pending slot fully solid (success/violet/amber) with dark numeral + dark dot; occupied/idle = neutral + accent outline; C/G badge dark glyph |
| Sources/UI/TrackSource/TrackSourceClipHistoryTabContent.swift:51, 74, 141 | Save Clip button, length pill, 16/32/64/128 options | R2 solid + dark text; unselected outline only |
| Sources/UI/TrackSource/TrackSourceClipHistoryTabContent.swift:280 | history region tile | R1 — neutral; accent border for selected/in-range |
| Sources/UI/TrackSource/TrackSourceClipHistoryTabContent.swift:404 | live-buffer fill region + write head | R1-wash + solid accent head line |
| Sources/UI/TrackSource/TrackSourceClipHistoryTabContent.swift:420, 487 | piano-roll notes / thumbnail notes | R2 solid |
| Sources/UI/TrackSource/Clip/ClipContentPreview.swift:797 (`chipButton`) | Lane / Length(16-32-64-128) / page segments | R2 solid thumb + dark text; unselected outline only |
| Sources/UI/TrackSource/Clip/ClipContentPreview.swift:910 | RUN MODE step cells | R2 solid violet + dark glyphs |
| Sources/UI/TrackSource/Clip/ClipPianoRollPreview.swift:45 | clip preview notes | R2 solid |
| Sources/UI/TrackSource/Generator/GridEditor.swift:38 | grid value bars | R2 solid |
| Sources/UI/TrackSource/Generator/PolyLaneSelector.swift:20 | LAYER lane pills | R2 solid violet + dark text |

#### Rest of the sweep

| Site | Element kind | Ruling |
| --- | --- | --- |
| Sources/UI/MixerView.swift:619 | insert icon badge | R2 solid + dark glyph |
| Sources/UI/MixerView.swift:784 | channel fader column + cap | R1-wash — neutral column (meters stay legible), solid cyan cap line |
| Sources/UI/TrackFillPreviewControl.swift:56 | FILL preview toggle | R1 body (neutral + accent outline) with R2 solid ON badge (dark text) |
| Sources/UI/Track/TrackWorkspaceView.swift:383 | "Open Kit View" pill | R2 solid + dark text |
| Sources/UI/Track/TrackWorkspaceView.swift:805 | record-progress region | R1-wash + solid accent head line |
| Sources/UI/Track/TrackWorkspaceView.swift:923 | StudioSegmentedControl thumb | R2 solid + dark text |
| Sources/UI/Track/ClipMacroLaneEditor.swift:110, 207 | macro count chip / override step cell | R2 solid cyan + dark text |
| Sources/UI/Slicer/SliceTrackWorkspaceView.swift:362, 743, 756 | page / length / layer pills | R2 solid + dark text |
| Sources/UI/Slicer/SliceTrackWorkspaceView.swift:567 | analysis panel | R1 — neutral; violet outline |
| Sources/UI/Slicer/SliceInspectorView.swift:135 | slice inspector panel | R1 — neutral; violet outline |
| Sources/UI/Slicer/SliceInspectorView.swift:212 | Reverse/Choke boolean buttons | R2 solid violet + dark text |
| Sources/UI/Slicer/SliceTrackEditingControls.swift:47 | clip layer selector pills | R2 solid + dark text |
| Sources/UI/Slicer/SliceTrackEditingControls.swift:550 | selected slice region over waveform | R1-wash — neutral region; identity in solid amber/violet boundary lines |
| Sources/UI/Slicer/SliceTrackEditingControls.swift:568 | S/E whole-handle labels | R2 solid success + dark text |
| Sources/UI/Slicer/SlicerSourceWidget.swift:106 | header icon badge | R2 solid cyan + dark glyph |
| Sources/UI/Slicer/SlicerSourceWidget.swift:283 | audition slice pads | R1 — neutral pads; kind in outline color |
| Sources/UI/Slicer/SlicerSourceWidget.swift:374 | analysis panel | R1 — neutral; violet outline |
| Sources/UI/Slicer/SlicerSourceWidget.swift:449 | Manual/Auto mode pills | R2 solid cyan + dark text |
| Sources/UI/Slicer/SlicerWaveformWindow.swift:118 | marker list row | R1 — neutral; cyan outline |
| Sources/UI/DrumGroup/DrumKitMatrixView.swift:529, 558, 672, 1367 | header action button, 16/32 thumb, layer thumb, routing-mode thumb | R2 solid + dark text |
| Sources/UI/DrumGroup/DrumKitMatrixView.swift:612, 689, 887 | MIXED / PATTERN MISMATCH / divergent-pattern badges | R2 solid amber + dark text |
| Sources/UI/DrumGroup/DrumKitTemplateChooserSheet.swift:129, 148 | OVERWRITES badge / template row | R2 solid badge; R1 row (success outline) |
| Sources/UI/DrumGroup/AddDrumGroupSheet.swift:147, 337 | kit chips / template chips | R2 solid + dark text |
| Sources/UI/Library/LibraryWorkspaceView.swift:100 | category nav row | R1 — neutral step + violet outline; violet count chip carries identity |
| Sources/UI/Theme/StudioCards.swift:74 | StudioAddCard "+" circle | R2 solid + dark glyph |
| Sources/UI/Mixer/MixerWorkspaceView.swift:222, 270 | send insert icon badge / selected row | R2 solid badge; R1 row (accent outline) |
| Sources/UI/Mixer/MixerWorkspaceView.swift:672 | MixerStripActionButton (active) | R2 solid + dark text |
| Sources/UI/Mixer/MasterOutputColumnView.swift:356 | unity-gain marker line | solid amber (was 0.85) |
| Sources/UI/PerformanceLayerSelector.swift:51 | performance layer option cell | R1 — neutral; solid accent outline + accent check |
| Sources/UI/SidebarView.swift:116 | sidebar nav row | R1 — neutral step (no accent wash) |
| Sources/UI/LiveWorkspaceView.swift:149, 183 | layer index pill / basis-phrase chip | R2 solid pill; R1 chip (violet outline + violet text) |
| Sources/UI/PhraseWorkspaceView.swift:829, 940, 1110 | matrix track header cell / phrase row fill / selection-only cell | R1 — neutral bodies; state in solid outlines + solid badges |
| Sources/UI/PhraseLayerPresentation.swift | `layerFill` helper (dead code) | deleted — banned pattern with no callers |
| Sources/UI/PhraseLaunchGrid.swift:89 | phrase launch cell | R1 — neutral; solid cyan outline |
| Sources/UI/PhraseCellEditorSheet.swift:215 | bar page pills | R2 solid + dark text |
| Sources/UI/PhraseCellEditors/PatternIndexPicker.swift:18 | P1–P16 pills | R2 solid violet + dark text |
| Sources/UI/RoutesListView.swift:91 | "Disabled" badge | R2 solid amber + dark text |
| Sources/UI/TransportBar.swift:205 | queued-phrase chip | R1 — neutral; amber outline + amber text |
| Sources/UI/TransportBar.swift:328 | TransportButtonStyle body | R1 — neutral step, brighter neutral when pressed; accent outline |
| Sources/UI/TrackDestination/MacroPickerSheet.swift:163 | parameter picker row | R1 — neutral step (checkmark carries the green) |
| Sources/UI/TrackSource/Generator/ProgressionChordGeneratorEditorView.swift:312, 358 | chord card / step cell | R1 — neutral; 2pt accent outline when selected |
| Sources/UI/TrackSource/Generator/ProgressionChordGeneratorEditorView.swift:397, 624 | layer buttons / chips | R2 solid + dark text |

Tally: **45 sites → R2 solid accent + dark glyphs**, **38 sites → R1 neutral
container + accent outline**, **5 → neutral wash + solid accent head**
(value/progress regions), **1 deleted dead helper**. After the sweep, no
`accent.opacity(…)` remains as any background/fill in Sources/UI; the
remaining `*.opacity` fills are white/neutral steps, hairline drawn rules,
or `accentFill` (1.0 = solid). Accent-opacity strokes (outlines) remain by
design.

Judgment calls worth knowing about:

- Channel fader fills (MixerView) were cyan washes so the meters could show
  through; they're now neutral washes with a solid cyan cap carrying the
  level. The master fader keeps its fully solid cyan block (solid is legal).
- Progress/region overlays (record progress, live-history buffer, selected
  slice region) became neutral washes with a solid accent head/boundary
  line, since solid accent would have hidden the data beneath.
- The dashed-accent strokes on Add cards and the 1px accent bottom rules on
  source/modifier wells were kept: they're drawn lines (outline idiom), not
  fills.

## Where it lives

Branch `feature/flat-ui-variant` (worktree `.worktrees/flat-ui-variant`),
now including the mixer overhaul merged from main (StudioMixerStrip scaffold,
StudioSlideControl, channel meters).

## Pass 2 — "bolder" (current)

Verdict on pass 1: "still looking quite washed out and low contrast". Pass 2
applies four binding directives derived from the reference image:

1. **One ground.** `StudioTheme.background` dropped to near-black (~#0d0d10)
   and `chrome`, `panel`, `panelFill`, `stageFill` all collapsed onto it —
   the window, top bar, stage, and panels are now literally the same colour.
   `StudioPanel` lost its fill entirely (panels are pure grouping); the
   stage lost its rounded plate + outline (`WorkspaceDetailView`). A control
   gets at most one fill step above ground (`subtleFill`) or none at all.
2. **Drawn-line outlines.** `StudioTheme.border` raised ~#454a54 → ~#62626c,
   and every standard 1px stroke swept onto a new
   `StudioMetrics.borderWidth = 1.5` token. Outline-only (no fill) is now
   the default idiom for inactive cells/pads/steps: step cells, phrase
   matrix cells, option cards, nav pills, circle icon buttons.
3. **Solid saturated accents.** Active states are fully solid fills with
   dark glyphs inside: step cells (cyan/amber blocks), mute cells (solid
   green "Live" / solid red "Muted" via new `StudioTheme.danger`), pattern
   slot pills, nav/transport-mode pills, phrase badges, layer-selector
   circles. Violet brightened, success green saturated, pattern palette
   saturation 0.62→0.78 / brightness 0.88→0.95. In-between accent washes
   removed (tinted chip/panel backgrounds became outline-only).
4. **Text contrast.** `text` ≈ #e8e8ec, `mutedText` ≈ #9a9aa4 (neutral, no
   darker functional text). VALUES now read in the accent colour like the
   reference's violet numerals: rotary knob values, slide-control/pan
   values, metric pills, BPM, transport position, mixer dB readouts, scalar
   phrase cells.

Key token moves (before → after):

| Token | Pass 1 | Pass 2 |
| --- | --- | --- |
| background | #0f1217 | #0d0d10 |
| chrome | #1a1c21 | = background |
| panel / panelFill | #21242b | = background |
| stageFill | #121419 | = background |
| inset | #0b0d11 | #060608 |
| border | #454a54 | #62626c |
| violet | (0.56,0.48,1.0) | (0.63,0.53,1.0) |
| success | (0.47,0.91,0.63) | (0.30,0.92,0.52) |
| danger | — (Color.red ad hoc) | (1.0,0.32,0.34) |
| subtleFill | 0.07 | 0.05 |
| selectedFill | 0.32 | 0.50 |
| stroke opacities | 0.14–0.80 | 0.30–0.95 |
| stroke width | 1 | 1.5 (`StudioMetrics.borderWidth`) |

Structural de-nesting beyond tokens:

- `StudioPanel` / `WorkspaceDetailView`: panel fill and stage plate removed.
- `StepGridView`: the per-step container plate (inset fill + own outline
  around `UnifiedStepCell`) removed — the cell is the control.
- Phrase matrix value cells: container fill removed; the cell preview block
  sits directly on the ground, container draws a line only when
  selected/inherited.
- `PatternIndexCellPreview`: tinted cell wash behind the slot matrix
  removed.

## Pass 1 (superseded)

Solid fills instead of gradients, no shadows, `StudioTheme.inset` wells,
crisp hairlines. Kept; pass 2 builds on it.

## How to run it

```
cd .worktrees/flat-ui-variant
open build-dd/Build/Products/Debug/SequencerAI.app
```

(Already built; rebuild with `xcodebuild build -project SequencerAI.xcodeproj
-scheme SequencerAI -destination 'platform=macOS' -derivedDataPath build-dd`.)

## What to compare first against the reference

1. **Tracks edit** (was 02-tracks-edit.png) — one near-black ground, cards
   outlined not filled, solid pattern-slot blocks.
2. **Mixer** (was 04-mixer.png) — strips as outlined columns on the ground,
   cyan dB values, pan values in accent.
3. **Phrase matrix with controls open** (was 10-phrase-controls-open.png) —
   solid green/red mute blocks with dark labels, outline-only idle cells,
   solid violet selection lines.
4. **Drum kit matrix / step grids** — solid cyan/amber active steps with
   dark glyphs, outline-only inactive steps (the closest analogue of the
   reference's pad rows).

## Verification

App builds; full suite run on the branch with the standard three skips
(audio-routing/device-switch flakies). `PhraseCellPreviewTests` updated for
the solid slot fill; other presentation tests mirror the tokens and moved
with the theme.
