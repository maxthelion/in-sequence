---
status: resolved
raised_by: pm-assistant
raised_during: draft-user-stories
created: 2026-04-30T11:16:45Z
resolved: 2026-05-03
resolved_by: user
resolved_in:
  - user decision on 2026-05-03
---

# Toggle Fill On A Track Concerns

## Concerns

1. **Runtime override versus phrase mutation is unresolved.**
   Story 3 depends on a transient preview model, but there is no `setLiveFill(trackID:)` path today. PM work should decide whether this is a live runtime override that shadows compiled phrase fill state, or a phrase edit that mutates the `"fill-flag"` layer.

2. **Generator-backed tracks cannot currently preview fill.**
   The engine only honours `fillEnabled` on the clip branch. If a track's active source is generator-backed, the fill toggle either needs a disabled/unavailable state or generator fill support must become a separate feature.

3. **Toggle placement remains unresolved.**
   The user goal is clear, but the exact placement in the track editor should be decided during prototype review rather than assumed in stories.

## Suggested Resolution Path

- Resolve the runtime override versus phrase mutation question in `existing-state.md` and `architecture.md`.
- Treat generator fill behavior as an explicit non-goal unless architecture review approves support.
- Prototype the track-editor placement before spec.

## User Decision

Accepted on 2026-05-03:

- Fill preview should be a transient runtime override, not a phrase mutation.
- The phrase `"fill-flag"` layer must not be mutated by the preview toggle.
- Generator-backed track support is out of scope for v1; generator-backed tracks should show a disabled/unavailable state or message.
- Toggle placement should be decided during prototype/UX review rather than in the user stories.
