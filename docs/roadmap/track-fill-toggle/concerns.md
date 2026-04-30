---
status: open
raised_by: pm-assistant
raised_during: draft-user-stories
created: 2026-04-30T11:16:45Z
resolved_in: []
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
