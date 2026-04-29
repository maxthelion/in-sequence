# Clip History UX Review

## User Feedback

The modal version is the stronger direction.

The prototypes did not fully understand the production application's current visual language, which is acceptable for rough Balsamiq-style exploration, but the next pass should better respect the app's structure.

## Direction To Keep

Use the modal pattern as the basis for the next design pass.

The modal should show:

- recent history clips as a 4x4 matrix on one side;
- the 16 pattern slots as a similar 4x4 element on the other side;
- a clear relationship between selected history region and target pattern slot;
- enough distinction between temporary audition state and committed clip state.

## What Failed Or Needs Another Pass

- The visual style and layout did not show enough awareness of the actual app.
- The history and pattern-slot concepts need a stronger side-by-side structure.
- The next pass should clarify the click path from "interesting generated output" to "audition pseudo clip" to "save as real clip."

## Architecture Questions To Resolve Before Spec

- How is recent step history stored in a lightweight way?
- How does scrubbing through history create a pseudo clip for audition?
- Where does pseudo-clip playback live so it does not become accidental document truth?
- At what exact action does the pseudo clip become a real persisted clip?
- How does this fit existing sequencer data patterns rather than forcing broad document rewrites?
