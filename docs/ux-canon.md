# UX canon

The product owner's UX judgment, canonized from his bug reports and review
feedback (2026-05 → 2026-06) so an observer can apply it to screenshots
without him present. Every rule below traces to feedback he actually gave;
sources are cited so an observer can read the original wording when a call
is ambiguous. When screenshots violate these rules, that is a finding —
file it like a bug report, citing the rule.

This document complements `docs/roadmap/mixer-style-guide.md` (mixer
specifics) and the design tokens in `Sources/UI/Theme/` (the mechanical
vocabulary). This is the taste layer above both.

## 1. State the header owns is never repeated in cells

When a header, layer selector, or section title already names the active
context, cells under it must not restate it. No per-cell layer labels, no
"SEL 1/8" badges echoing the header's variant, no captions repeating what
the section title says.

- A cell shows *its own* state only ("Muted", "HELD", "P3"), never the
  shared context it sits inside.
- Symptom pattern: a chip in every cell of a grid all saying the same
  thing ("SINGLE" × 18, "Pattern slot" × 18, "No default destination" × 8).
  One fact, one place.

Sources: 2026-06-10 note-repeat cell reports ("the text on them with the
icon is still redundant"), QA review P1.10, input-audio feedback
(STATE/MONITOR/CHANNEL bubbles duplicating segmented controls).

## 2. The whole cell is the control

If a layer or mode is selected, each cell IS the toggle/control for that
layer — no buttons inside cells, no pickers at cell feet, no inner "+
Assign" affordances inside grid cells. The interaction surface is the full
cell; the displayed state is one big word or value filling it. Empty space
at the bottom of a cell is waste.

Sources: "If a layer is selected, we don't need buttons in each of the
cells… the whole cell should be the toggle"; "a lot of empty space at the
bottom of the cell, which is a waste" (2026-06-10).

## 3. No explainer prose on surfaces

The UI must explain itself by shape, not sentences. Any full sentence on a
working surface is a finding: "plays once, then advances to the next
phrase", "0 is unlimited", "Track cards return after a layer…",
"Selection only", "Add one to process the resolved source…". Help text
belongs in tooltips (`.help`), not the layout.

Corollary: internal API or model names never appear on screen ("Rows
follow TrackGroup.memberIDs order.") and raw IDs are never user-facing
labels ("Sample B63D8DFA" — resolve to the library name).

Sources: QA review P1.9, kit-matrix caption feedback, routing-sheet
feedback.

## 4. Edit in place

Controls live in or on the thing they edit. Selecting an item expands it
or opens a focused editor — it does not spawn a panel elsewhere on the
page. Phrase length/repeat edit inside the phrase's own box; a separate
below-the-row panel is the anti-pattern. Heavy machinery (creation flows,
routing) goes in a StudioModal with the shared modal grammar.

Sources: 2026-06-10 phrase-UI report ("the latter two should be in the box
on the left for editing… this should be removed").

## 5. One grid grammar

Anywhere steps appear, they are the same step editor: same cell
components, same size, same beat grouping, same layer controls. A matrix
of steps is the step editor showing more rows, never a miniature
"representation" of one. Pattern selection is a 1–16 row in the standard
style, at group level where parts play together.

Same-kind cards have the same dimensions: an Add card matches the cards it
sits among (not shorter, not taller). Rate/option pickers are full-size
cells, not chips at card feet.

Sources: 2026-06-06 kit-matrix feedback ("steps in each drum-part row are
far too small… should share a common interface with the other step
sequencer element"), QA review P1.11.

## 6. Tokens, never raw chrome

All radii, spacing, type sizes, and opacities come from StudioMetrics /
StudioTypography / StudioOpacity / StudioTheme. Any of the following in a
screenshot is a finding:

- stock white scrollbar tracks, white-filled buttons, stock blue focus
  rings, system slider thumbs (pan and continuous values are rotary knobs);
- a one-off corner radius / font size that matches no token;
- a bare ✕ where the circled-✕ standard component exists.

Sources: QA review P1.8/P1.14, mixer review, HTML prototype guidelines in
`docs/roadmap/intent.md`.

## 7. Text never deforms

State words and labels must survive the minimum window width without
truncation or wrapping: "NOT…", "LI/VE", "MUTE SI…", "Post fa…" are all
findings. If a label can't fit, the label is wrong (use the compact
vocabulary: MUTE / FILL / VOL / PAN…), not the layout. Vertical letter
stacks (B/P/M) are never acceptable.

Sources: QA review P0.1/P0.2, mixer review.

## 8. Nothing clips, everything scrolls

At the default window size, no content is cut off below the fold or at a
container edge: step grids, part lists, selector rows, history buffers.
If content can exceed the space, the container scrolls — with themed
scroll indicators, not stock ones.

Sources: QA review P0.3, kit matrix "6 parts" with 5 visible.

## 9. Vertical strips align across kinds

In any side-by-side strip layout (mixer channels, buses, master): equal
widths for same-kind strips, the same element at the same vertical
position across all strip kinds (fader with fader, meter with meter,
header with header), strips kept narrow, and no element escaping its
strip's bounds. A master/special column is a sibling in the layout, never
an overlay occluding others.

Sources: 2026-06-10 mixer UX review ("elements being similar in different
kinds of vertical busses, alignment of similar elements, keeping busses
narrow, keeping elements within ui boundaries").

## 10. Progressive disclosure, grouped flows

Reveal complexity in steps that mirror the user's decision order (e.g.
creation: sounds first, then patterns, then routing). Group interactions
that belong to the same part of the flow; don't scatter one decision
across the page. Don't show advanced options before the basic choice is
made.

Sources: kits/templates creation-modal direction, roadmap working-process
UX checklist ("progressive disclosure, not repeating information, grouping
interactions that form a similar part of the flow").

## 11. Performance surfaces read at a glance

Perform-mode cards and cells are momentary instruments: one dominant state
word, strong on/off color distinction (Muted red / Live green class),
captured context as a small second line at most ("STEP 5 · 1/8"). MOM /
LATCH and other mode state lives once in the header bar, not per card.

Sources: note-repeat/fill cell feedback, perform-layer card reports.

## 12. Color identifies, it never floods

Over the near-black ground, translucent accent composes into muddy
mid-tones ("orange translucent on top of grey… a mess"). Accent colour
names a thing or a state; it never fills an area:

1. **Containers are never tinted.** Cards, panels, wells, tab bodies, and
   sections fill with the ground or the single neutral step above it.
   State/identity on a container is carried by its OUTLINE colour
   (selected scene = orange outline on a dark card) plus at most one small
   SOLID badge inside (the solid orange "A" chip).
2. **Small elements go fully solid.** Pads, step cells, badges, pills,
   value chips, and segmented-control thumbs carry state as fully solid
   accent fills with dark glyphs/text — never translucent.
3. **Values may be accent text.** Numerals and value labels can render in
   the accent colour directly.
4. **Translucent accent fills are banned at every scale.**
   `accent.opacity(…)` / `stateColor.opacity(…)` must not appear as any
   background or fill — composing accents into `StudioOpacity` fill tokens
   counts. Hover/pressed feedback uses the neutral fill step or outline
   brightening, never an accent wash.
5. **Neutral fills are opaque tokens, not opacity recipes.**
   Structural grey backgrounds use `StudioTheme` solid fill roles such as
   `subtleFill`, `borderSubtleFill`, or `inset`. `Color.white.opacity(…)`
   and `StudioTheme.background.opacity(…)` are banned for surface chrome
   because nested controls otherwise get lighter with every level.

Limited-colour amendment (2026-07-06): colour does not identify track type,
pattern number, phrase layer mode, source category, or arbitrary control
category. Transport uses the fixed app accent. Track detail, slicer, audio
input, drum-kit, and track-source surfaces use the focused track/kit identity
accent. Phrase perform/layer surfaces use the phrase accent, except where a
cell is explicitly identifying a track. Pattern slots are numbered positions,
not a rainbow palette. Red/amber/green are reserved for true danger,
warning/recording, and completed/available semantic states.

Sources: 2026-06-11 flat-UI pass-2 review (scene A/B cards, perform track
cards, Track Source editor screenshots), reference image in
`docs/bugs/20260611-142049-i-d-like-the-ui-to-be-flatter-more-like/`.

## How an observer applies this

1. Take the latest QA capture set (gallery or
   `.meta/multipass/runtime/loops/project/observe/qa-surface-coverage/`).
2. Sweep every capture against rules 1–12; collect findings as
   `rule → capture(s) → exact element → suggested fix`.
3. Verify a suspected finding by cropping at full resolution before filing
   (thumbnails lie about truncation).
4. File findings in a dated review doc under `docs/bugs/` in the style of
   `2026-06-10-qa-surface-review.md`, ranked P0 (looks broken) / P1 (canon
   violation) / P2 (polish), each citing the rule number.
5. Patterns beat instances: ten cells with the same bug is one finding
   about the component, not ten findings.
