---
verdict: accepted
selected_prototype: phrase-button-controls.html + matrix-navigation-and-layers.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/phrase-button-controls.html
  - prototypes/matrix-navigation-and-layers.html
feedback_applied: []
---

# Phrase Features — UX Review

Reviewed 2026-04-30 against user stories, existing-state findings, and the HTML
prototype guidelines checklist.

---

## Prototypes reviewed

| File | Stories covered |
|---|---|
| `phrase-button-controls.html` | 1 (bar count), 2 (repeat count), 3 (loop toggle), 4 (annotation only) |
| `matrix-navigation-and-layers.html` | 5 (page-nav arrows at matrix corners), 6 (fixed-width layer selector) |

---

## Guideline checklist

### Aesthetic / tone

- Both files use monochrome greyscale as the structural base with a single blue
  (`#0060df`) accent for interactive elements and a gold (`#ffd700`) accent for
  the loop state. Color is semantic-only.
- System font stack only. No shadows, gradients, or decorative flourishes.
- Stub regions are clearly hatched with dashed borders and muted text — pass.
- Slightly polished (clean rounded corners on steppers) but still clearly not a
  production mock. Does not fail the "could be mistaken for production" test.

### Information architecture

- `phrase-button-controls.html` uses progressive disclosure: phrase rows are
  collapsed by default; tap the phrase button to expose its controls. One
  primary action per interaction (adjust bar count, adjust repeat count, toggle
  loop). Secondary controls are in the expanded panel only.
- `matrix-navigation-and-layers.html` keeps navigation arrows and the layer
  selector spatially separated (header row vs footer row) while using the same
  3-column grid template to enforce alignment.

### Behavior

- Steppers update their displayed value and the "Effective playback behaviour"
  summary in real time.
- Loop toggle changes label text, fills gold, and overrides the behaviour
  summary. The override relationship is communicated both visually and textually.
- Page-nav arrows update their active/inactive class and occupancy badge when
  pages are navigated — all done in real time with fixture data.
- Layer selector width stays constant at 220 px across all layer names (Pattern,
  Transpose, Variance %, FX Send, Mute). No layout shift demonstrated by the
  comparison panel.

### Interaction budget

- Both files state the budget explicitly (≤2 interactions for phrase controls;
  ≤1 for page nav and layer switch).
- The click-paths are annotated in the budget box and exercisable in the
  prototype. Budget is satisfied.

### Fixture data

- `matrix-navigation-and-layers.html` uses adversarial track names: "Bass
  Synth", "Pad (long)", "Lead Mélodie" (diacritic), "Arpegg." (truncated),
  "FX Noise". Eight tracks across two pages.
- `phrase-button-controls.html` uses "Phrase D (Outro Bridge)" — a long name
  that forces font-size reduction. The name overflows the 90 px button cell at
  normal size, and the prototype handles it by reducing font-size to 10 px.
  This is worth flagging but is not a rejection blocker.
- Repeat-count and loop-toggle state are cross-linked: setting repeat count to 0
  and toggling loop both produce an "infinite" result, and the behaviour summary
  calls out the redundancy clearly. This is the correct treatment for an ambiguous
  design space.

### Scope discipline

- Story 4 (perform save-back) is correctly stubbed. The annotation box explains
  why a wireframe was deferred and what architecture prerequisite is needed. This
  is the right call — prototyping a staging layer without a spec for it would be
  misleading.

---

## Per-variant evaluation

### `phrase-button-controls.html` (Stories 1–3, 4 stub)

**What works**

- The expand-on-tap pattern keeps the phrase list compact in the default state
  and surfaces the three controls only when needed. This is exactly what the
  user story acceptance criterion asks for ("without leaving the main view").
- Bar count and repeat count steppers are operable with two taps (open panel,
  tap stepper). The controls are in a single horizontal row — easy to scan.
- The loop-toggle badge on the collapsed phrase header (Variant C) is clear:
  the gold tint and loop symbol make the state readable without opening the
  panel. "Phrase B" (playing + loop on) demonstrates that the playing-active
  blue and the loop-gold badge coexist without collision.
- The "Effective playback behaviour" summary text is a strong communicative
  choice: it translates the three independent controls into a single sentence
  that describes what will actually happen. This removes ambiguity about the
  interaction between repeat-count=0 and loop-toggle.
- The annotation for Story 4 correctly places a design boundary without
  pretending to design what cannot yet be designed.

**What fails or is weak**

1. Redundancy between repeat-count=0 and loop-toggle is surfaced correctly in
   the behaviour summary, but the prototype does not prevent the user from
   setting both. This creates two ways to express "loop forever". Whether this
   is a model decision (loop-toggle overrides; repeat-count is read when
   loop is off) or a UI decision (loop-toggle disables the repeat stepper) is
   left open. This is an architecture question, not a UX rejection.

2. The phrase button width is fixed at 90 px. "Phrase D (Outro Bridge)" overflows
   and is handled by font shrinkage. Real phrase names in the app should be
   assumed to be user-defined and potentially long. The production implementation
   should use text truncation with a tooltip, not font shrinkage. This is a
   non-blocking implementation note.

3. Only Phrase A is interactive in Variant A; Phrases B, C, D are stubbed. For
   a review of the per-phrase panel this is acceptable, but if phrase panels
   ever have different defaults (e.g. Phrase B has a non-infinite repeat count),
   a second expanded variant would be helpful. Not a blocker for advancing.

4. The prototype does not show what happens when bar count is decreased on a
   phrase that already has step data beyond the new length. This is an
   architecture question (existing-state §7 notes there is no step-truncation
   behaviour today) rather than a UX gap in the prototype itself.

**Story coverage**

| Story | Covered | Notes |
|---|---|---|
| 1. Bar count control | Yes — interactive stepper | Works in ≤2 taps |
| 2. Repeat count | Yes — interactive stepper | 0=∞ representation is clear |
| 3. Loop toggle | Yes — toggle with badge in collapsed state | Override of repeat count is communicated |
| 4. Perform save-back | Annotation only | Correctly deferred |

---

### `matrix-navigation-and-layers.html` (Stories 5–6)

**What works**

- The 3-column grid (`32px 1fr 32px`) for both the matrix header and the layer
  bar is a clean structural solution. It guarantees that the layer selector and
  the nav arrows occupy the same column spans at both ends of the matrix, giving
  the layout a consistent visual bracket.
- The occupancy badge (count in a small circle on the arrow) is informative:
  navigating from page 1 shows "4" on the right arrow, confirming there are four
  tracks on the next page. The arrow greys and the badge disappears when there
  is no adjacent page — clear binary signal.
- The comparison panel for Story 6 (current vs proposed layer selector) directly
  demonstrates the fix. Switching layers in the proposed panel shows no width
  change; switching in the current-state panel (where the width is content-driven)
  shows visible shift for "Pattern" → "Transpose". The before/after is compelling.
- Track names in the demo include "Lead Mélodie" (diacritic + accented character)
  and "Arpegg." — names that would break naive width assumptions. The fixed-width
  layer selector handles these without layout shift.

**What fails or is weak**

1. The prototype leaves open whether "no adjacent page" should grey the arrow or
   hide it entirely. Both are shown as static reference variants but neither is
   argued for. This is a product decision the prototype correctly flags as an open
   question. Should be resolved before spec.

2. The layer selector is 220 px fixed. On narrow devices this could crowd the
   track names. The annotation notes that text will truncate (ellipsis) rather
   than expand, which is the right approach — but the minimum safe device width
   is not specified. Not a blocker; architecture/spec should state a minimum
   layout width.

3. The grid row spacers (the 32 px columns in body rows) are left empty/grey.
   In the actual UI these columns are either wasted space or could carry
   row-level controls (phrase bar numbers, mute toggles). This is outside the
   scope of this prototype but worth noting so the spec addresses whether those
   columns serve any purpose beyond alignment.

4. The phrase sidebar in the matrix demo is stubbed (click does nothing). This is
   correct scope discipline — Story 5 is about matrix corner arrows, not phrase
   switching. No issue.

**Story coverage**

| Story | Covered | Notes |
|---|---|---|
| 5. Page arrows at matrix corners | Yes — interactive, with occupancy badges | Open question: grey vs hidden when empty |
| 6. Fixed-width layer selector | Yes — comparison panel with live demo | 220 px value; min-width not validated |

---

## Overall assessment

### What works across both prototypes

- The interaction budgets are met.
- Both files use the same semantic color system and could be referenced by the
  same implementation.
- The structural decision to share a 3-column grid across the matrix header and
  the layer bar (Story 5 + 6) is architecturally coherent with existing-state §5
  and §6 and eliminates the current placement confusion.
- Story 4 is handled correctly as an annotation deferral — it would be a mistake
  to prototype it without the staging architecture defined.

### Open questions to carry forward

1. **Loop-toggle vs repeat-count-zero redundancy**: should the UI disable the
   repeat stepper when loop-toggle is on, or allow both to be set and have the
   toggle always win? This affects the model spec for `repeatCount` and
   `loopEnabled`.

2. **No-adjacent-page arrow treatment**: grey/dim vs hidden. User preference
   question — should go into `open-questions.md` if the spec writer cannot
   resolve it from context.

3. **Grid row spacer columns**: define what occupies the 32 px gutter columns in
   body rows in the spec.

4. **Bar-count decrease with existing step data**: what happens to steps beyond
   the new phrase length? This is an architecture question for `write-architecture`.

5. **Minimum layout width for fixed-width layer selector**: state in spec or
   architecture.

---

## Recommended direction

Accept both prototypes as the design direction. They cover Stories 1, 2, 3, 5,
and 6 with sufficient fidelity to proceed to architecture. Story 4 (perform
save-back) must be treated as a separate track within this feature: architecture
first, prototype second.

The two open questions that could affect model/architecture decisions (loop-toggle
redundancy; no-adjacent-page arrow treatment) should be carried into
`open-questions.md` and resolved before or during `write-architecture`. They do
not block that stage but must be answered before `write-spec`.

**Selected prototypes:**
- `phrase-button-controls.html` — chosen direction for Stories 1–3
- `matrix-navigation-and-layers.html` — chosen direction for Stories 5–6
- Story 4: deferred pending staging-architecture design
