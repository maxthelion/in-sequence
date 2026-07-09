Macros view is inconsistent with other tracks. We should use the same ui element for drum kits, slicer, mono, chord, audio etc. I like these big empty states. The spacing should be more uniform within the space.

Screenshots:
- 21-track-macros-tab.png

Capture references:
- 21-track-macros-tab.png (in-sequence/qa-surface-coverage; main @ 53e42ea6; run 20260707-215434-in-sequence-qa-surface-coverage-main-53e42ea6; 9ec629c201f3d75ef938b916a3ec9ef9)

Status: RESOLVED 16ac1dea; verified by qa-surface-coverage run 20260708-090903-in-sequence-qa-surface-coverage-main-923a889d row 21-track-macros-tab.

Follow-up: RESOLVED (uncommitted, 2026-07-08); the first fix only covered the
normal track macro tab. Updated the shared macro-slot presentation so workspace
macro tabs use the same large unlabeled slot grammar and surface accent across
normal track, drum-kit kit tab, drum-kit expanded-part tab, slicer, and chord.
Verified with qa-surface-coverage run
20260708-124942-in-sequence-qa-surface-coverage-main-d2ac498a rows
21-track-macros-tab and 29b-drum-kit-macros-tab.
