---
verdict: accepted
selected_prototype: 01-part-workspace-header.html + 02-kit-step-matrix.html + 03-group-routing-editor.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/01-part-workspace-header.html
  - prototypes/02-kit-step-matrix.html
  - prototypes/03-group-routing-editor.html
feedback_applied: []
---

# Drum Parts As A Group — UX Review

Reviewed 2026-04-30 against user stories, existing-state findings, and the
HTML prototype guidelines.

---

## Checklist

| Check | Result |
|---|---|
| Single HTML file, no build step | Pass — all three files self-contained |
| Monochrome base with semantic colour only | Pass — dark greyscale base; amber for mismatch warning, green for active/accent |
| Stubs marked with dashed borders and placeholder text | Pass — transport, pattern bank, off-path areas clearly dashed |
| Adversarial fixture data | Pass — "808 Bones" (long kit name), 6 parts (tests nav bounds), generator part, Clap with per-part override, mixed-pattern state |
| Same fixtures reused across variants | Pass — all three prototypes use 808 Bones / Kick / Snare / Clap / Closed Hat / Open Hat / Rim Shot |
| Interaction budget stated and annotatable | Pass — each file documents the budget and click-path in its header comments |
| Primary goal reachable via expected click-path | Pass (see per-variant analysis below) |
| Differences between variants are strategic not cosmetic | Pass — each prototype covers a distinct story cluster, not a cosmetic restyle |
| Stubs unmistakable without being told | Pass — no stub area could be mistaken for production UI |
| Progressive disclosure respected | Pass — routing editor is not on the primary matrix screen; reached via "Edit Routing…" |
| Not too polished to mistake for production | Pass — clearly Balsamiq-level |

---

## Per-Variant Analysis

### 01 — Part Workspace Header Navigation (Stories 1 & 2)

**What works well:**

- The kit-header band is a tight, appropriate addition to the part view. Left/right arrows plus the "X of N in [Kit Name]" counter solve Story 1's "done when" criteria completely: part name visible, position visible, navigation bounded (disabled arrow at edge).
- The kit colour strip (3 px, `TrackGroup.color`) is a low-cost identity signal that answers prototype open question Q3 affirmatively — it should stay.
- Generator-part state is handled correctly: navigation arrows remain active (the user can still move to other parts), step grid dims and shows an explanatory notice. This directly addresses user-story assumption on read-only generator parts.
- The "Open Kit View" button is subordinate to the nav controls in size and position. The kit label above it contextualises which kit the user is in. This hierarchy is correct.
- Kit-view overlay shows the close button as "← Back to [Part Name]", which preserves the user's place per Story 2's "done when."

**What fails or is incomplete:**

- The overlay body is completely stubbed ("see prototype 02"). A reviewer cannot experience the transition from the overlay into a real matrix. This is acceptable given the scope split across files, but the implementation loop must treat prototypes 01 and 02 as a pair for this story.
- Open question Q1 (wrap vs. disabled at edges) is unresolved. The prototype defaults to disabled. No user-story requirement forces a choice here. Leave for spec; note it as a deferred decision.
- Open question Q2 (overlay vs. push navigation) is unresolved. The overlay model demonstrated works for a quick glance; push navigation would be more appropriate if the user intends to stay in the kit matrix for several operations. This is a real open question — see open-questions.md.

**User-story coverage:**

- Story 1: Covered completely by the default and first/last-part states.
- Story 2: Covered in structure; overlay body is stubbed.

---

### 02 — Kit Step Matrix (Stories 3 & 4)

**What works well:**

- The part-name + slot-badge + step-row layout is the right information hierarchy for Story 3. Part names are fixed-width on the left, step pattern runs right — the groove is readable at a glance.
- Pattern coherence signal (amber slot badges + warning banner) directly addresses Story 4's "done when" requirement: "it is obvious when parts are not set to patterns that would be heard together." The mixed-patterns state demonstrates this effectively.
- The "[generator — read only]" badge on the Open Hat row correctly communicates the read-only constraint from the user-story assumptions.
- Read-only step cells with the "Tap row to edit [part] in part view" tooltip elegantly directs the user to the correct editing surface without blocking visibility.
- The 16 / 32 step toggle shows awareness of pattern-length variation (existing-state §7 noted that each part has its own `TrackPatternBank` with independent length).
- "Edit Routing…" button is properly subordinate — small, in the header, not a primary action.
- The kit pattern selector stub is correctly deferred with a visual label.

**What fails or is incomplete:**

- The `solo-kick` state dims non-selected rows to 30% opacity, but there is no per-row mute affordance in this view. The existing model has `TrackGroup.mute` (group-level) and no per-member mute. The "Mute Kit →" button in the action bar is correctly dashed/stubbed. This gap should be noted in open questions but it does not block acceptance.
- Prototype Q5 (per-member mute representation) remains unaddressed. The user stories do not require per-part mute in the matrix view, so this is correctly out of scope here.
- Tapping a row triggers `alert('[STUB] → Opens [part] workspace')`. The return path from the matrix to a specific part is not demonstrated in the prototype itself — it relies on the same `Back` button in the action bar that closes the whole view. This is acceptable for this stage but the spec must clarify whether row-tap is a push navigation (replacing the matrix) or returns to the previously focused part view.
- Prototype Q4 (push vs. inline expander on row tap) is unresolved. Leave for spec.

**User-story coverage:**

- Story 3: Covered completely. Step matrix renders all parts with names on the left.
- Story 4: Covered completely. Active pattern slot is visible per part; mismatch is highlighted.

**Acceptance signal check:**

- "Kit matrix view shows the whole kit in one screen; no horizontal scrolling needed to see the part names." — Pass for 16-step mode on a 420 px frame. The 32-step mode compresses steps to fit, which is acceptable.
- "Immediately obvious when two parts are on different patterns." — Pass (amber badges + warning banner).

---

### 03 — Group Routing Editor (Stories 5 & 6)

**What works well:**

- The two-section layout (Section A: group destination, Section B: trigger mapping mode) maps cleanly to Stories 5 and 6. The information hierarchy is correct: global destination first, mapping mode second, per-part assignments third.
- The `Per MIDI Note` / `Per MIDI Channel` / `Individual` segmented control is the right UI primitive for the trigger-mapping mode decision. It is legible, the active state is distinct, and switching updates the per-part rows immediately.
- The model-gap warning banner in channel mode is an excellent practice: it surfaces a genuine architecture constraint (existing-state §6 — no per-member channel field, no `triggerMappingMode` enum) inline in the prototype rather than burying it in notes. The spec writer and implementer cannot miss it.
- "Shared / Own" toggles per part correctly implement the `inheritGroup` / individual-destination toggle described in existing-state §5. The Clap row starting with `[override]` is a good adversarial fixture.
- The destination field greying out in Individual mode is correct behaviour.
- The Apply / unsaved-changes state is properly represented with the amber-tinted Apply button and "Unsaved changes" label.
- The absolute note name display (C2, D2, D#2…) is more user-friendly than raw offsets, and the tooltip correctly explains the underlying offset mechanism.

**What fails or is incomplete:**

- Open question Q1 (is `triggerMappingMode` a new persisted enum, or derived from the shape of `noteMapping`?) is unresolved and is a genuine architecture decision. Existing-state §6 confirms the enum does not exist. This must be resolved at the architecture stage, not here.
- Open question Q2 (data-loss risk when switching from note mode to channel mode) is unresolved. The spec must address this. The prototype does not guard against it.
- Open question Q5 (relationship to `AddDrumGroupSheet`) is unresolved. Treating this as a standalone post-creation edit sheet is a reasonable default; the spec should confirm whether they share a component.
- The note name input fields accept free text (e.g. "C2") but the underlying data is an integer offset from baseline 36. The prototype does not show what happens with invalid input. The spec must define the note-name → offset mapping and validation.

**User-story coverage:**

- Story 5: Covered completely. Group destination field is editable, per-part inherit toggle is present, individual overrides are shown.
- Story 6: Covered for note mode; channel mode is shown with the correct model-gap warning. The "done when" criteria for Story 6 require the channel assignment to be shown per row — this is demonstrated even in the gap-flagged state.

**Acceptance signal check:**

- "Setting a shared destination does not require opening each part individually." — Pass.
- "Trigger mapping mode (channel vs. note) is visible and editable per kit, not buried in individual part settings." — Pass.

---

## Flow Coherence Across Prototypes

The three prototypes form a coherent linear flow:

1. User is in a drum part's step editor → kit header band (01) → tap "Open Kit View"
2. Kit matrix view opens (02) → step overview at a glance → tap "Edit Routing…"
3. Routing editor sheet (03) → set destination, mapping mode, per-part assignments → Apply

The return path (Back from routing → matrix → Back from matrix → return to prior part) is logically consistent, though not fully interactive across files. The spec must make this navigation contract explicit.

---

## Concerns

**Moderate: Navigation model ambiguity (overlay vs. push)**

Prototypes 01 and 02 treat the kit matrix as an overlay sheet launched from within the part view. But in 02, the matrix also has a "Back" button in its own action bar. If the kit matrix is a destination users stay in (to scan the groove, compare patterns, edit routing), an overlay is inappropriate — it implies a quick glance, not a workflow step. If users typically dip into the matrix briefly and return, the overlay is correct.

The spec should state the intended use pattern and pick either overlay-sheet (quick reference) or push-navigation (workflow destination). This is a product decision, not a UX failure of the prototypes.

**Minor: Part row tap ambiguity in matrix**

In prototype 02, tapping a row is supposed to open that part's workspace. But there is also a "Back" button that returns to the previously focused part. The interaction between these two actions — row tap vs. back button — is not differentiated enough. If row tap is a navigation action, it should look like a navigation affordance (e.g. a disclosure chevron), not just a hoverable row.

**Minor: Note name field is under-specified**

Prototype 03 shows note names as editable text inputs (e.g. "C2"). The underlying model uses integer offsets from baseline 36. The spec must define the note-name editor precisely, including how names are parsed and what happens on invalid input.

---

## Recommended Direction

Accept all three prototypes as the basis for architecture and spec work. The three-file split maps naturally to three distinct surfaces:

1. **Part workspace header band** — kit nav + kit view launch button (01)
2. **Kit step matrix** — read-legible groove overview, pattern coherence signal, routing entry point (02)
3. **Group routing editor** — shared destination, trigger mapping mode, per-part assignments (03)

No rework is required before architecture. The model-gap warnings in prototype 03 (no `triggerMappingMode` enum, no per-member channel field) should be taken directly into the architecture phase. The open questions around overlay vs. push navigation and note-name editing should be resolved in the spec.

The following open questions should be carried forward:

- Q: Overlay vs. push navigation for the kit matrix from the part view.
- Q: Does tapping a row in the kit matrix push to that part's workspace or return to the previously focused part?
- Q: `triggerMappingMode` — new persisted enum on `TrackGroup`, or derived from noteMapping shape? (Architecture decision.)
- Q: What is the note-name editor format and validation rule for `noteMapping` values?
- Q: Data-loss policy when switching trigger mapping mode (note → channel).
- Q: Does the routing editor panel reuse `AddDrumGroupSheet` or is it a standalone post-creation sheet?
