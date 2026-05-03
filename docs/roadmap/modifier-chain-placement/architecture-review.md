---
verdict: accepted
reviewed: 2026-05-03
reviewer: codex
---

# Modifier Chain Placement Architecture Review

## Outcome

Accepted with revisions.

The architecture is coherent enough to advance to spec. It correctly treats
`SourceRef` as playback truth, keeps picker state transient, and limits the
feature to slot-scoped source/modifier editing rather than a broader track model
rewrite.

## Approved Guardrails

### 1. **Slot-scoped source truth is the right boundary**

The feature should operate on the selected `TrackPatternSlot`, not every slot in
the track's bank. This matches the existing model in [[arch:persisted-document-data]]
and the current gap analysis in [[arch:architecture-constraints]].

*Suggested resolution:* Carry this into `spec.md` as a hard acceptance
criterion: every source/remove/add operation names the selected slot index.

### 2. **`SourceRef` should remain canonical playback state**

The architecture correctly avoids a second UI-owned source model. The engine
already compiles playback from `SourceRef`, and nil clip state already has a
defined silent behavior. The slot well should only present and mutate that
document truth.

*Suggested resolution:* Spec should reject view-local playback overrides and
make the slot well a view over `TrackPatternSlot.sourceRef`.

### 3. **Empty source state should use existing document shape**

Using `.clip` mode with `clipID == nil` is the smallest model change. It avoids
placeholder clips and matches `SourceRef.isEmpty`.

*Suggested resolution:* Add a dedicated slot-scoped remove operation, but do not
add a new persisted empty-source enum or auto-created placeholder clip.

### 4. **Picker and disclosure state should stay transient**

Open picker branches, selected picker rows, and disclosure depth are UI state,
not project state. That fits the feature's UX problem and keeps the document
model focused on musical data.

*Suggested resolution:* Keep this in SwiftUI state or small helper view models
under `Sources/UI/TrackSource/`.

## Revised Guardrails

### 1. **Prefer explicit plus after remove over auto-open**

The architecture leaves auto-open versus explicit plus as a product choice.
Given the approved prototype feedback asks for more progressive disclosure, the
spec should prefer: remove source -> show empty slot well -> user opens the
source picker with the plus/primary action. Auto-opening the full picker after
remove makes the fast path shorter, but it also collapses two decisions into one
moment and works against the user's IA feedback.

*Suggested resolution:* Spec the explicit empty-well state as the default. If a
future shortcut is added, it should be additive and reversible rather than the
only path.

### 2. **Bank-level generator helpers are legacy compatibility, not the new path**

`attachNewGenerator`, `removeAttachedGenerator`, and `switchAttachedGenerator`
rewrite all slots in a bank. The architecture correctly flags them as the wrong
ownership level, but the spec should be firmer: the slot-well feature must not
call those helpers for selected-slot changes.

*Suggested resolution:* Spec narrow document helpers for selected-slot
operations and reserve bank-wide helpers for existing legacy flows or an
explicit future "apply to all slots" feature.

### 3. **`attachedGeneratorID` should not block the feature, but divergence must be contained**

The architecture identifies `attachedGeneratorID` as a risk. This does not need
another architecture pass, because playback truth is already `SourceRef`. The
spec should treat `attachedGeneratorID` as compatibility metadata unless the
implementation proves it is still required for a live path.

*Suggested resolution:* Require tests that selected-slot generator changes do
not unexpectedly fan out through `attachedGeneratorID`; defer any cleanup of the
field to a separate refactor unless needed for correctness.

## Risks The Architecture Pass Missed Or Understated

### 1. **Editing an empty clip slot can still create a clip indirectly**

The architecture says clip creation must remain explicit, but current editing
paths call ensure-and-mutate helpers when the clip editor changes. If the empty
source state continues to render an editable clip grid, the first edit may
create a blank clip implicitly and blur the difference between "empty source"
and "blank clip."

*Suggested resolution:* Spec that an empty source well does not show the active
clip editor as if a clip exists. Clip creation happens through the explicit
"new blank clip" branch.

### 2. **Modifier selection currently creates a clip in one branch**

The current modifier selection code can call `ensureClipForCurrentPattern` when
the selected slot is clip-mode with no clip. That is probably a legacy safety
behavior, but it conflicts with a strict empty-source model if left unexplained.

*Suggested resolution:* Spec modifier behavior for an empty source slot. The
most conservative rule is: adding a modifier should not create source material;
it should attach the modifier to the slot state and leave source selection
separate.

### 3. **The picker needs shared option primitives, not another one-off sheet**

The architecture recommends focused subviews, which is right, but the existing
`GeneratorSelectionSheet` is generator-only. The new feature will need clip
pool, generator pool, blank clip, blank generator, and modifier-compatible
branches. Without a shared slot-option primitive, implementation may duplicate
picker behavior.

*Suggested resolution:* Spec one source/modifier slot picker structure with
branch-specific rows and compatibility filters, rather than separate bespoke
sheets for each branch.

## Open Architecture Questions

No user-blocking architecture questions remain.

The spec still needs to make product choices concrete for empty states,
modifier options, and picker dismissal, but the architecture review can answer
the main model questions without asking the user for another decision.

## Recommendation

Advance to spec.

The spec should consume [[arch:application-invariants-the-feature-must-preserve]]
and the revisions above as binding guardrails. The strongest build direction is
a selected-slot source/modifier well that:

- mutates only `TrackPatternSlot.sourceRef`;
- uses `.clip` with `clipID == nil` for explicit empty source state;
- reveals secondary picker branches progressively;
- avoids bank-wide generator helpers for slot-well operations;
- keeps all picker/disclosure state transient;
- makes clip creation explicit.
