# Post-Merge Feedback: Fill Preview Placement

Date: 2026-06-06
Feature: Track Fill Toggle / Fill Preview
Source: product-owner review of merged UI

## Feedback

The Fill Preview control has landed as a tab-like item in the track source
interface, next to Source, Modifier, and History. That placement feels wrong.

Fill Preview is not a source-section mode. It is a track/pattern playback
preview affordance. Putting it in the tab row makes it read like another
content section, and it competes with the source/modifier/history grammar.

## Desired Direction

Move the Fill Preview control out of the source tab row. It likely belongs near
the pattern context, possibly above or near the pattern numbers, where it can
read as “preview this track/pattern in fill mode” rather than “switch to a Fill
Preview tab.”

The exact placement may need a small UI exploration, but the rework should:

- preserve the existing transient fill-preview behavior;
- avoid making Fill Preview look like a fourth track-source tab;
- keep the control close to the pattern/track context it affects;
- ensure disabled/unavailable state remains clear for unsupported sources;
- avoid adding a large permanent panel for a transient preview action.

## Attribution

Likely introduced by the Track Fill Toggle feature:

- `1d4e333 Add selected track fill preview header`
- `103f6db Add track fill preview visual capture helper`
- `36e804a Merge branch 'auto/roadmap-18-track-fill-toggle' into integration/track-fill-toggle-clean-20260604T2204Z`
