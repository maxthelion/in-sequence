# Design review — 61 captures, post-salvage main (2026-07-03)

Confirmed by adversarial verification: 31 · refuted: 2 · low-severity nits: 15 · clean captures: 14

## Confirmed findings

### [HIGH] 02a-tracks-selection-actions
**Rule:** Rule 12 (color identifies, never floods)

The selected 'Phrase Nav Track' card is rendered as a FULL solid-orange fill, flooding the whole container with accent.

*Fix shape:* Rule 12.1 is explicit: containers are never tinted; selection/identity on a card is carried by its OUTLINE colour plus at most one small solid badge (compare 02-tracks-navigator, where selected 'Mono 6' correctly uses only a cyan outline). Here selection-mode floods the entire track card orange, dropping the 'MONO' subtitle to near-illegible dark-on-orange. Same flooded-orange state is visible (dimmed) on the active card behind the modal in 02c, so this is a component-state bug, not a one-off.

*Verifier:* Confirmed: in 02a the entire "Phrase Nav Track" card is filled solid orange (MONO subtitle near-illegible dark-on-orange), whereas selection elsewhere (Mono 6 in 02-tracks-navigator) uses only a thin outline — a clear breach of Rule 12.1's "containers are never tinted; identity via outline plus one small badge."

### [HIGH] 02d-add-drum-group-modal
**Rule:** Rule 3 (no explainer prose on surfaces)

The Add Drum Group modal is saturated with full-sentence explainer prose across all three sections.

*Fix shape:* Offending strings: 'Step 1 — 0 parts, editable after kit pick', 'No parts yet', 'Step 2 — optional template, applied into pattern slot 1', 'No template — parts start with blank patterns.', 'Step 3 — output bus and optional shared destination', 'Recommended — the kit gets its own mixer bus you can process as one unit.' Rule 3 states any full sentence on a working surface is a finding ('Add one to process the resolved source…' is cited verbatim). This is ~6 sentences, far beyond a modal's single sanctioned subtitle slot; this content should be shape/badges + .help tooltips.

*Verifier:* The modal visibly carries full explainer sentences across all three sections — notably "Recommended — the kit gets its own mixer bus you can process as one unit." (near-identical to Rule 3's cited "...to process the resolved source…") and "No template — parts start with blank patterns." — plus three step-descriptor subtitles, which is well beyond a single sanctioned subtitle and genuinely breaches Rule 3.

### [HIGH] 04-mixer.png
**Rule:** Canon Rule 6 (no stock white scrollbar tracks / stock chrome)

The mixer shows a bright stock horizontal scrollbar along the bottom edge and a stock grey vertical scrollbar on the right, instead of themed scroll indicators.

*Fix shape:* Rule 6 explicitly bans 'stock white scrollbar tracks'. The bottom bar is a light-grey OS scrollbar over the near-black ground; Rule 8 requires themed scroll indicators when content overflows.

*Verifier:* A bright light-grey stock macOS horizontal scrollbar (with a visible pale track) sits along the bottom edge from ~x80–630, and a stock grey vertical scrollbar thumb appears on the right edge (~x1120), both unmistakably system chrome over the near-black ground — a clear breach of Rule 6 (no stock white scrollbar tracks) and Rule 8 (themed scroll indicators required on overflow).

### [HIGH] 05d-scenes-bitcrusher-editor.png
**Rule:** Canon Rule 6 (tokens, never raw chrome — continuous values are rotary knobs; no system slider thumbs/steppers)

The Bitcrusher FX editor (right panel) uses naked horizontal sliders with system round thumbs for RATE (50%) and DRIVE (0%), plus a stock up/down stepper on 'Bits: 12'. Continuous values must be rotary knobs.

*Fix shape:* Directly contradicts the sibling filter editor in 05b, which correctly renders CUTOFF/RESONANCE as themed rotaries. The bitcrusher panel is the only surface in the set using stock sliders + a system stepper. Same panel also leaves large empty space below the three controls.

*Verifier:* Confirmed: the Bitcrusher panel renders Rate (50%) and Drive (0%) as horizontal system sliders with round white thumbs plus a stock up/down stepper on "Bits: 12", whereas the SCENE MACROS below correctly use themed rotary knobs — a direct breach of Canon Rule 6 (continuous values must be rotaries, no system slider thumbs/steppers).

### [HIGH] 08-phrase-layers-pattern.png
**Rule:** Rule 7 (text never deforms; no vertical letter stacks) + Rule 8/9 (nothing clips / no element escaping bounds)

The 'Perform' control at the top-right corner of the LAYERS well is squeezed into a tall, thin strip so its label deforms. In 08 it renders as a vertical character stack reading 'Pe / r / or / m / O / n'; in 09 and 10 it collapses to a bare orange vertical bar with no legible text; in 10a/10b/11 it wraps to three lines 'Perf / Orm / On' inside a narrow orange oval. Vertical letter stacks are explicitly banned by Rule 7. This same mangled control appears in ALL SIX captures.

*Fix shape:* The header 'Perform' button (seen normal-width in the 13-track-perform prototype) is being laid out into a sliver of width at the right edge of the well, forcing the label to stack/wrap. The control needs its natural width or to move out of the well's right gutter.

*Verifier:* The right-edge control of the LAYERS well renders as a tall narrow orange pill with its "Perform On" label deformed into a vertical character stack ("Pe/r/or/m/O/n"), a clear Rule 7 vertical-letter-stack violation.

### [HIGH] 18-track-detail-steps-clip.png
**Rule:** D-grammar (value/layer selectors = solid thumbs in inset capsule track) + canon Rule 12 (color never floods a container)

The LAYER selector is rendered as a full-width, solid-cyan accordion bar ("LAYER  Steps" / "LAYER  Pitch" with a disclosure chevron) instead of the approved inset-track segmented control (Steps / Velocity / Chance solid thumbs in a darker capsule, per prototype 08-D mono-track.png).

*Fix shape:* This is the single largest accent flood in the app: a container-sized element filled solid cyan, which point 1 of Rule 12 forbids (containers are never tinted). Same bar appears in 22c (LAYER Pitch). When opened (22d) it reveals Steps/Pitch/Velocity/Chance as big full-width grey buttons in a 2x2 stack -- also not the inset-thumb grammar. The approved control is an always-visible compact segmented control, not a collapsible dropdown.

*Verifier:* Confirmed: the LAYER selector is a full-width bar flooded entirely solid cyan with a dropdown chevron, breaking Rule 12 (color floods a container-sized element, not a small thumb) and diverging from the inset-capsule segmented-control grammar used by its own sibling selectors LANE and LENGTH directly above it.

### [HIGH] 20b-track-randomize-settings.png
**Rule:** canon Rule 6 (no system slider thumbs / stock chrome; continuous values are rotary knobs) + Rule 3 corollary (no raw model names)

The Randomize Clip modal uses naked horizontal system sliders for DENSITY / VELOCITY / GATE, stock native pop-up buttons for Root and Scale, and native up/down steppers for OCTAVE and SPAN -- wholesale divergence from the approved 12-clip-randomize prototype, which uses rotary knobs and pill grids.

*Fix shape:* Rule 6 explicitly bans system slider thumbs (continuous values must be rotary knobs) and stock combo boxes. The Scale value reads "minorPentatonic" (raw camelCase enum) rather than "Minor Pentatonic", violating the Rule 3 corollary. Same violations in 20c. Bake button is solid green (state-colour green used as an action fill).

*Verifier:* Confirmed: the Randomize Clip modal shows DENSITY/VELOCITY/GATE as horizontal system sliders with visible round native thumbs (clear Rule 6 breach), native pop-up buttons for Root/Scale plus native up/down steppers for OCTAVE/SPAN, and the Scale field reads raw camelCase "minorPentatonic" (Rule 3 corollary), all as described.

### [HIGH] 22e-track-generator-trigger-tab.png
**Rule:** canon Rule 6 (no white-filled buttons / stock chrome)

The generator picker is a stock white-filled native pop-up button ("Mono Generator" / "Progression Chords" / "Poly Generator"), a bright white control on the near-black ground.

*Fix shape:* Rule 6 lists white-filled buttons and stock chrome as findings. Recurs across 22e, 22f, 22g, 22h. In 22f the same white native dropdowns are used for "Pitch Expander: Manual" and "Harmonic Sidechain: None". These should be themed dropdowns/segmented controls.

*Verifier:* Confirmed: the "Mono Generator" generator picker is a bright white-filled native macOS pop-up button (with stock chevron) on the near-black themed surface, exactly the white-filled button / stock chrome that canon Rule 6 bans, while every neighbouring control is properly themed dark.

### [HIGH] 24-audio-idle.png
**Rule:** State-colour fence (tab-unification DECISION, 2026-07-03) / Rule 12

The audio-input surface adopts GREEN as its entire chrome accent — the solid SOURCE section pill, the full-panel well stroke, the dashed 'Add Audio Input' card outline, and the 'Rolling capture' Write-Target selection outline are all green.

*Fix shape:* The locked State-colour vocabulary fences GREEN to 'SMALL SOLID state elements only (badges, dots, rec strips) — never outlines, well strokes, or container chrome, which belong exclusively to the surface accent.' Here green is the surface chrome: well stroke + section-switcher pill + two selection outlines. Same violation appears in 25-audio-live.png. The audio track needs a non-fenced identity accent for its chrome; reserve green for small live/capturing state marks only.

*Verifier:* Confirmed: in 24-audio-idle.png green is the audio surface's chrome accent — solid SOURCE section pill, full-panel well stroke, dashed 'Add Audio Input' card outline, and 'Rolling capture' selection outline (plus the PATTERN eyebrow underline) are all green, i.e. outlines/well-stroke/container-chrome, exactly what the 2026-07-03 State-colour fence forbids for GREEN (allowed only for small solid state badges/dots/rec-strips).

### [HIGH] 25-audio-live.png
**Rule:** Rule 12.1 (containers never tinted) + State-colour fence

The 'Audio Channel / St 1-2 / 2 channels / Change' source card is filled SOLID GREEN with dark text and dark L/R meters — a whole container flooded with accent.

*Fix shape:* Rule 12.1: containers fill with the ground/neutral step; identity is carried by OUTLINE plus at most one small solid badge — never a solid card fill. Compounded because the fill colour is green, which is fenced to small solid state elements. This is the worst instance of the audio-surface green flooding.

*Verifier:* The "Audio Channel / St 1-2 / 2 channels / Change" source card is a full solid-green container fill with dark text and dark L/R meters, sitting beside correctly-neutral dark cards — a clear breach of Rule 12.1 (containers never tinted; identity via outline + small badge only) compounded by the green state-colour fence.

### [MEDIUM] 01a-song.png
**Rule:** State-colour fence + Rule 12 (colour identifies, never floods; identity on containers is the OUTLINE, but state colours are fenced off container chrome)

The "Breakdown" phrase-label card (left column, third row) has an amber/orange OUTLINE around the whole card and an amber-highlighted "Unlimited" repeat field, while the other phrase cards are grey and the selected "Phrase A" card is purple-outlined. Amber (pending/divergent) is fenced to small solid elements and must not be a container outline; it also introduces a second accent competing with the purple selection outline on the same surface.

*Fix shape:* Carry the divergent/unlimited state as a small solid badge/dot inside the card, not as a full amber card outline.

*Verifier:* The "Breakdown" phrase card in the left column has a full amber/orange outline around the whole card (plus an amber-tinted "Unlimited" field), while other cards are grey and the selected Phrase A is purple-outlined — amber used as container chrome, which the state-colour fence (canon-creep lines 154-160) explicitly forbids, restricting amber to small solid badges/dots.

### [MEDIUM] 02a-tracks-selection-actions
**Rule:** Accent discipline / one accent per surface

The selection-action toolbar color-roulettes sibling toggles: 'By Track' is solid purple while 'By Value' is solid cyan.

*Fix shape:* Two peer selection-mode toggles carry two different accent fills on the same toolbar (and 'Selecting' cyan + 'Delete' amber add more). 02b renders the same By Track/By Value pair consistently in one purple grammar, so the two-colour treatment here is inconsistent and violates one-accent-per-surface.

*Verifier:* Confirmed: on 02a the peer selection-scope toggles render as a solid purple "By Track" beside a solid cyan "By Value" (with cyan "Selecting" and amber "Delete" also on the bar), whereas 02b renders the same By Track/By Value pair in a single consistent purple segmented grammar — cyan/purple are not fenced state colours, so this is genuine per-toggle accent roulette breaching one-accent-per-surface.

### [MEDIUM] 02d-add-drum-group-modal
**Rule:** Accent discipline / one accent per surface (Rule 12)

Three different chrome accents color-roulette across the modal: cyan, purple, and green section underlines and selector thumbs.

*Fix shape:* SOUNDS + title underline = cyan, PATTERNS underline = purple, ROUTING underline = green; matching selected value thumbs KIT 'Blank' = cyan, TEMPLATE 'None' = purple, OUTPUT 'New bus: Drum Group' = green. The locked grammar mandates one accent per surface (no per-tab colour roulette). Additionally the green OUTPUT pill misuses a fenced STATE colour (green = capturing) as a non-state selection fill.

*Verifier:* Confirmed in the PNG: SOUNDS underline + KIT 'Blank' thumb render cyan, PATTERNS underline + TEMPLATE 'None' thumb render purple, and ROUTING underline + OUTPUT 'New bus: Drum Group' thumb render green — three chrome accents rouletting across one modal, breaching the locked 'one accent per surface / no per-tab colour roulette' grammar, with green additionally misusing the fenced capturing-state colour as a selection fill.

### [MEDIUM] 02d-add-drum-group-modal
**Rule:** Rule 6 (tokens, never raw chrome)

The '+ Add part' button is a stock white-filled button.

*Fix shape:* Rule 6 lists 'white-filled buttons' as an explicit finding. On the near-black modal ground this solid-white pill is raw chrome; it should be a themed outline/accent control.

*Verifier:* Confirmed: the "+ Add part" control is a solid white-filled pill with dark text sitting on the near-black modal ground — the sole white-filled button among otherwise state/accent-colored pills (teal KIT, purple TEMPLATE, green OUTPUT), matching Rule 6's explicit "white-filled buttons" finding and not sanctioned by the accent state-colour vocabulary in Rule 12.

### [MEDIUM] 02e-add-slice-track-loop-picker
**Rule:** Weirdness (wrong-looking data)

Captures 02e and 02f show the wrong surface — both are byte-identical to 02d's Add Drum Group modal.

*Fix shape:* 02e is named 'add-slice-track-loop-picker' and 02f 'create-track-sound-step', but both render the Add Drum Group modal verbatim (all three PNGs identical). The intended slice loop-picker and sound-step surfaces were never captured; the harness appears to have stalled on the drum-group modal. Needs re-capture before those surfaces can be reviewed.

*Verifier:* Confirmed: 02e (named add-slice-track-loop-picker) and 02f (create-track-sound-step) both render the "Add Drum Group" modal verbatim — 02f is md5-identical to 02e (900e4f5a…) and 02e is visually identical to 02d's drum-group modal, so the intended slice loop-picker and sound-step surfaces were never captured; minor imprecision is that 02d's PNG is not literally byte-identical (md5 c84d9c71…) though visually the same modal.

### [MEDIUM] 05-scenes-browse.png
**Rule:** State-colour vocabulary (GREEN fenced to small solid state elements only — never outlines/chrome)

The 'Add Scene' card is a large GREEN dashed outline enclosing a green + circle. Green is reserved for capturing/live and may only appear as small solid state elements, never as container outline/chrome.

*Fix shape:* An Add-Scene affordance is not a capturing/live state. Also inconsistent with the orange 'Add FX' affordance used one screen over (05a), so the two add-zones read as two different accent systems. Same green Add-Scene card recurs in 05e.

*Verifier:* The 'Add Scene' card uses a green dashed container OUTLINE plus a green + glyph; the fence explicitly bars green from outlines/container chrome (green = capturing/live state only, small solid elements), and an add affordance is not a live state — a genuine breach, and it clashes with the orange surface accent on the adjacent real scene cards.

### [MEDIUM] 05b-scenes-edit-content.png
**Rule:** Canon Rule 6 (bare ✕ where the circled-✕ standard component exists)

The scene FX insert rows (Visual Filter, Visual Crusher) each terminate in a bare ✕, but the standard circled-✕ exists and is used in the Add FX modal (05c).

*Fix shape:* Same bare ✕ appears on the insert rows in 05d. The circled-✕ is the established component, so the insert rows should use it.

*Verifier:* Zoomed crop confirms each insert row (Visual Filter, Visual Crusher) ends in a plain grey bare ✕ with no surrounding circle, while the same surface's "Add FX" affordance uses a circled "+", so the circled-symbol standard exists and the bare ✕ breaches Canon Rule 6.

### [MEDIUM] 05e-scenes-browse-fx.png
**Rule:** Canon Rule 7 (text never deforms — no truncation/wrapping of labels)

Scene-card stat lines are clipped: 'Empty Scene / 0 inserts - 0 ma…' and 'Scene With Inserts / 2 inserts - 2 ma…', and the insert chips read 'Visual Filt…' and 'Visual Cr…'.

*Fix shape:* '0 ma…' / '2 ma…' cut off 'macros'; the FX chips cut off the effect names. Same '0 inserts - 0 ma…' truncation appears on the cards in 05-scenes-browse. If the label can't fit, the label/vocabulary is wrong, not the layout.

*Verifier:* Both scene cards visibly truncate their stat line to "0 inserts - 0 ma…" / "2 inserts - 2 ma…" (cutting off "macros") and the FX chips read "Visual Filt…" and "Visual Cr…" with ellipses — exactly the truncation Canon Rule 7 ("Text never deforms," e.g. "Post fa…") forbids.

### [MEDIUM] 07-library
**Rule:** Accent discipline / one accent per surface

The two column headers use different chrome accents: 'GLOBAL LIBRARY' underline (and the selected 'Breaks' pill) are purple, while 'PROJECT POOL' underline is cyan.

*Fix shape:* Two side-by-side panels on one Library surface carry two different accent colours for equivalent header/eyebrow chrome — colour roulette. Pick one surface accent for both columns.

*Verifier:* Confirmed: on one Library surface the "GLOBAL LIBRARY" eyebrow underline (and the selected "Breaks" pill outline) sample as purple RGB(161,135,255)/(127,108,198) while the equivalent "PROJECT POOL" eyebrow underline samples as cyan RGB(0,204,255) — two different chrome accents for equivalent header chrome, a genuine breach of "one accent per surface / no color roulette" and not covered by the fenced green/amber/red state-colour vocabulary.

### [MEDIUM] 10a-phrase-density-zero.png
**Rule:** Rule 12 (color identifies, never floods; well strokes belong exclusively to the surface accent) + tab-unification 'one chrome accent per surface'

The LAYERS surface carries two chrome accents at once. The section identity is purple — LAYERS tab, the BY TRACK/BY VALUE segmented thumb, PATTERN dropdown, VALUE, and AUTOMATION are all purple chrome — yet the well is outlined in ORANGE and the MOM/Perform controls are orange. A well stroke must carry the single surface accent (purple here), not a competing orange. Seen in 08/09/10/10a/10b/11.

*Fix shape:* Per the locked D grammar and the State-colour section, container chrome / well strokes belong exclusively to the surface accent; orange fighting purple on the same surface is the 'more than one chrome accent per surface' violation.

*Verifier:* The LAYERS surface identity is purple (LAYERS tab, BY TRACK thumb, PATTERN, AUTOMATION all purple chrome), yet the well is stroked in orange and the MOM/Perform controls are orange; an orange well stroke competing with the purple surface accent breaches the locked D grammar's "one chrome accent per surface" and the State-colour rule that well strokes/container chrome belong exclusively to the surface accent and never carry a state colour.

### [MEDIUM] 11-phrase-layer-selector-open.png
**Rule:** Rule 3 (no explainer prose on surfaces) + Rule 1 (state the header owns is not restated)

The open layer-selector dropdown shows three option cards each with a subtitle explainer under the label: MUTE / 'track mute', PATTERN / 'pattern slot', FILL / 'runtime fill'. These restate the label in lower-case filler. 'pattern slot' is the exact string canon Rule 1 cites as creep and the tab-unification audit lists for purge.

*Fix shape:* The label alone (MUTE/PATTERN/FILL) is self-explanatory; the subtitle line is redundant explainer prose that Rule 3 says belongs in .help tooltips, not the surface.

*Verifier:* The open MUTE/PATTERN/FILL selector cards each carry a lower-case subtitle ("track mute"/"pattern slot"/"runtime fill") that merely restates the label — redundant explainer prose that breaches ux-canon Rule 3 and Rule 1 (whose symptom list literally cites "Pattern slot"), and which the tab-unification audit already flags for purge ("NO subtitle explainers", TrackWorkspaceView.swift:601-633).

### [MEDIUM] 12-phrase-scenes.png
**Rule:** State-colour fence (tab-unification doc): state colours are SMALL SOLID only, never outlines/chrome

The "Discard" pill (header, right cluster, between the green solid "Capture" pill and orange "Perform On") is rendered as a GREEN OUTLINE pill with green text. Green is a fenced state colour (capturing) and is explicitly barred from outlines/chrome — it may only appear as a small SOLID element. Same green-outlined Discard recurs in 13, 13a, 13c.

*Fix shape:* Make Discard neutral chrome (or solid if it must carry the capture-session accent); reserve green for the solid Capture pill only.

*Verifier:* Confirmed: the "Discard" pill renders as a transparent green-outline pill with green text (between the solid-green "Capture" pill and the solid-orange "Perform On"), and green as an outline/stroke violates the state-colour fence which permits green only on small SOLID elements, never outlines/chrome.

### [MEDIUM] 13-phrase-global-apply.png
**Rule:** Rule 2 (whole cell is the control) + Rule 5 (full-size cells, no foot labels) + one-accent consistency across same-kind cards

The three BY-VALUE cards are inconsistent. MUTE and FILL are orange-outlined cards each filled edge-to-edge by one big solid value pad ("Mixed"), but the middle PATTERN card is cyan/blue-outlined, shows an empty step-grid preview, and puts a small "Mixed" text label at the card foot. Different outline colour, different fill treatment, and a foot label instead of a full-cell value word — the PATTERN card reads as half-baked next to its siblings.

*Fix shape:* Unify the three cards: same outline accent, and let the PATTERN card show its value the same full-cell way (or, if a grid preview is intended, drop the redundant foot "Mixed" label per Rule 5).

*Verifier:* Confirmed: MUTE and FILL show the value as one full-cell solid pad, but the PATTERN card demotes its "Mixed" value to a small foot label beneath an empty step-grid preview (plus a differing cyan outline), which breaches Rule 5's ban on foot-labels/miniature grids and Rule 2's whole-cell-is-the-control; the red/green pad fills themselves are sanctioned state colours and not part of the defect.

### [MEDIUM] 13-phrase-global-apply.png
**Rule:** Tab-unification DECISION: one chrome accent per surface; the well stroke carries the section accent

The layer control-row well is outlined in ORANGE while its own section pill ("LAYERS", top-left) and its BY TRACK/BY VALUE sub-toggle are PURPLE. Two chrome accents fight on one surface, and the well stroke no longer ties to the section accent. In 01-phrase (perform off) the identical well is purple-outlined — so the orange stroke here is driven by perform-on state bleeding into container chrome. Recurs in 13a and 13c.

*Fix shape:* Keep the well stroke on the section (purple) accent; carry perform-on state as a solid element (the Perform On pill already does), not by recolouring the well outline.

*Verifier:* Confirmed: the layer control-row well is stroked amber/orange (tracking the active Perform On state) while its own section accent is purple (LAYERS pill + BY TRACK/BY VALUE toggle), so a state colour is bleeding into container chrome — explicitly forbidden by the locked rule that well strokes carry only the surface accent and amber is fenced to small solid state elements.

### [MEDIUM] 21-track-macros-tab.png
**Rule:** canon Rule 1 (one fact, one place) + Rule 2 (whole cell is the control, no inner +Assign affordances)

The empty MACROS well shows eight identical "+" / "Assign" slots, each with a redundant "Assign" caption repeated 8 times.

*Fix shape:* Rule 1 cites exactly this symptom ("No default destination" x8). Rule 2 bans inner "+ Assign" affordances inside grid cells -- the whole cell should be the assign target with the label carried once.

*Verifier:* The MACROS well shows eight identical dashed "+" circles each captioned "Assign" with wasted space below, while the tab badge already reads "Empty" — a near-verbatim instance of Rule 2's banned inner "+ Assign" grid-cell affordance (whole cell should be the assign target, label carried once) plus Rule 1 redundancy.

### [MEDIUM] 22f-track-generator-pitch-tab.png
**Rule:** D-grammar accent discipline (one chrome accent per surface = the track-type identity colour, here cyan)

An off-palette purple/violet accent recurs on cyan-accented surfaces: the PITCH MODIFIER section underline (22f, 22h), the "Lane 1" pill (22h), and the SEND B value "0%" in the mixer (22b, while SEND A is cyan).

*Fix shape:* The tab-unification decision fixes one chrome accent per surface; purple was explicitly called out as a stray selection colour to eliminate. Purple is neither the cyan surface accent nor a fenced state colour (green/amber/red).

*Verifier:* The PITCH MODIFIER section underline measures RGB (161,135,255) purple/violet, while the sibling PATTERN underline and all other chrome on the surface are cyan (0,204,255) — an off-palette second accent on a section underline, which Variant D forbids (one chrome accent per surface; purple is not a fenced state colour).

### [MEDIUM] 22h-track-generator-chord-consumer.png
**Rule:** canon Rule 3 (no explainer prose on surfaces)

Explainer sentences sit on the generator surface: "Runs after the selected source" (under PITCH MODIFIER) and "1 lanes over the selected source".

*Fix shape:* Rule 3: any full sentence on a working surface is a finding; belongs in a .help tooltip. "1 lanes over the selected source" also has a singular/plural bug (should be "1 lane"). "Runs after the selected source" also appears in 22f.

*Verifier:* Under PITCH MODIFIER the surface plainly shows the two explainer sentences "Runs after the selected source" and "1 lanes over the selected source" (the latter also with the "1 lanes" singular/plural bug), which are exactly the full-sentence-on-a-working-surface prose Rule 3 bans in favor of .help tooltips.

### [MEDIUM] 23-track-slicer.png
**Rule:** Rule 3 (no explainer prose on surfaces)

The empty STEPS well shows a full explanatory sentence: 'No sample' / 'Choose a sample in the Source tab first.'

*Fix shape:* Rule 3: 'Any full sentence on a working surface is a finding.' The 'No sample' title is fine as a status; the instructional sentence should move to a .help tooltip or be dropped.

*Verifier:* The STEPS well shows a bold "No sample" status title (acceptable) followed by the full instructional sentence "Choose a sample in the Source tab first." — a genuine Rule 3 violation (explainer prose on a working surface, matching the canon's own example forms).

### [MEDIUM] 23a-track-slicer-populated.png
**Rule:** Rule 12 (solid accent = small elements only)

The slicer STEPS well's LAYER selector renders as a full-width (~1000px) SOLID purple bar/dropdown ('LAYER  Slice Index' with chevron), a large accent flood rather than a small element.

*Fix shape:* Recurs in 23b (LAYER Velocity) and 23c (LAYER Chance). The ground-truth prototype (11-step-layer-system slicer) uses an inset-track solid-thumb segment for the layer selector, not a full-width solid bar. Adjacent LANE (Normal/Fill) and LENGTH (16/32/64/128) correctly use small inset thumbs — the LAYER row should match them (or be an outline capsule with accent text), not a full-width solid fill.

*Verifier:* Confirmed: the LAYER "Slice Index" selector renders as a full-width (~1000px) edge-to-edge solid purple bar/dropdown with chevron, a large accent flood that violates Rule 12 ("small elements go fully solid," accent never floods an area) and breaks parity with the adjacent LANE/LENGTH inset-track thumbs the canon requires for the slicer layer row.

### [MEDIUM] 23fa-slice-layer-quick-switch.png
**Rule:** Weirdness — wrong/failed capture

23fa is pixel-identical to 23f (the 'Slice Source' modal) instead of showing the slice-layer quick-switch dropdown its filename promises.

*Fix shape:* Both show the same Slice Source modal (Normalize, waveform, Zoom/Scroll, Method Transients/Grid, Bars 1/2/4, 10 slices, Sensitivity 0.35, Cancel/Apply). The intended layer quick-switch state was never reached, so that surface has no coverage.

*Verifier:* 23fa is byte-identical to 23f (same SHA-256, 221545 bytes) and renders the same "Slice Source" modal rather than any slice-layer quick-switch dropdown, so the intended surface has zero coverage — a genuine wrong/failed capture.

### [MEDIUM] 23g-step-edit-rotaries.png
**Rule:** Weirdness — wrong/failed capture

23g ('step-edit-rotaries') shows the SOURCE tab (Atlantis Amen / 8 slices / Edit Slices / Re-slice), essentially identical to 23d, not any step-edit rotary editor.

*Fix shape:* The capture did not reach the per-step rotary edit state its name describes; the SOURCE panel is shown instead, so the step-edit-rotary surface is uncovered.

*Verifier:* 23g shows the SOURCE tab (highlighted purple) with the Atlantis Amen / 8 slices · Grid detection / Edit Slices / Re-slice panel — the same surface as 23d's source-tab capture — with no step-edit rotary editor visible, so the capture failed to reach the state its name describes.

## Low-severity nits (unverified)

- **01-phrase.png** — In LAYERS > VALUE, each track's 4x4 grid lights one cell on a red→orange→yellow→lime→green ramp to encode value magnitude. That ramp reuses the entire fenced state palette (red=recording, amber=pending, green=capturing), so a value cell can be misread as a transport/capture state. Same ramp in 01a-song and 01b-transport-swing-set.
- **01-phrase.png** — In the control row, BY TRACK/BY VALUE correctly uses an inset dark capsule track with a purple thumb, but the adjacent layer selectors PATTERN (dropdown) / VALUE / AUTOMATION render as free-floating solid/outline pills rather than the mandated inset-track solid-thumb form for value/layer selectors. Same in 01b.
- **08-phrase-layers-pattern.png** — Each track card's mini step-grid lights a single cell in a hue that cycles through a red -> orange -> yellow -> green rainbow across Mono 2..8 (Phrase Nav red, Mono2 orange, Mono3 yellow, Mono4 green, Mono5 red, ...). The per-track hue rotation reads decorative rather than semantic. Seen in 08/10/10a/10b/11.
- **07-library** — Each sample row has two identical unlabeled cyan '+' circle buttons with no way to tell them apart.
- **02-tracks-navigator** — The add-track affordance is a solid-green '+' circle, using a fenced state colour for a non-state action.
- **02c-create-track-modal** — The 'Input' track-type card uses a green container OUTLINE as its type identity.
- **02b-tracks-layer-perform-nav** — The track-name header is truncated to 'Phrase Nav Tr…' above the pattern grid.
- **05a-scenes-edit-empty.png** — Every empty Scene-Macro slot M1–M8 repeats the word 'Assign' under a dashed + knob — 'Assign' ×8, the exact 'No default destination ×8' symptom Rule 1 names.
- **05b-scenes-edit-content.png** — The FX/macros surface mixes rotary ring accents: CUTOFF ring is cyan while RESONANCE ring is orange; in the macro strip M1 CUTOFF is cyan and M2 DRIVE is orange.
- **04-mixer.png** — The Master strip carries a horizontal '1 —o— 2' slider with a naked round thumb below the 0 dB fader.
- **18-track-detail-steps-clip.png** — In the pattern row, the selected/edited pattern (4) is a solid green fill and pattern 1 carries a green outline ring, conflating selection chrome with the fenced green state colour.
- **18-track-detail-steps-clip.png** — The delete (trash) button top-right carries an orange rounded-rect outline on a cyan-accented track surface -- a second chrome accent, and an amber-family colour used as an outline.
- **22d-track-layer-quick-switch.png** — A stock-looking light vertical scrollbar appears at the right edge of the scrolled generator/layer captures (22d, 22e, 22f, 22g, 22h) rather than a themed scroll indicator.
- **23e-track-slicer-slice-tab.png** — The slice-detail waveform is rendered entirely GREEN, while the main track waveform (23a-23d, 23g) is cyan/blue.
- **23f-slice-source-modal.png** — In the Slice Source modal the Method (Transients/Grid) and Bars (1/2/4) segmented controls render their SELECTED thumb as neutral grey rather than the surface accent.

## Refuted (for transparency)

- **13a-phrase-global-apply-track-selector.png** — claimed: The toggle reads "ALL 8 TRACKS" (active, solid orange), but none of the 8 track cards below (Phrase Nav Tr…, Mono 2–8) s — refutation: "ALL 8 TRACKS" is a header-owned global-apply scope toggle (capture is "global-apply"), so the grey cards are the sanctioned state — and canon Rule 1 ("state the header owns is never repeated in cells") means filling all 8 cards orange to echo the header would itself be the violation, so the finding is refuted.
- **10a-phrase-density-zero.png** — claimed: An unexplained cluster of vertical bars (two bright-green bars plus one dark-grey bar) floats in the top-right of the LA — refutation: Refuted: the two vertical pills (one solid green = on, one green-outlined = off) sit fully inside the LAYERS well with clear gaps to the top border, right edge, and the separate orange Perform circle — they neither escape bounds (Rule 9), clip (Rule 8), nor collide; they read as an intentional state-coloured toggle pair, not broken meters. (The real corner defect is the orange button's wrapped "Perf/orm/On" text — a Rule 7 issue, not what this finding alleges.)

## Clean

05c-scenes-add-fx.png, 06-phrase-scenes-perform.png, 06a-phrase-scene-select.png, 06b-phrase-scenes-perform-slots.png, 06c-phrase-scenes-membership.png, 13b-phrase-perform-capture.png, 19-track-detail-sound.png, 19a-track-detail-sound-empty.png, 20-track-fill-preview-active.png, 20a-track-fill-engaged.png, 22-track-detail-fx.png, 23b-track-slicer-velocity-layer.png, 23c-track-slicer-chance-layer.png, 23d-track-slicer-source-tab.png