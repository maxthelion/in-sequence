# note-repeat

- loop: `build/note-repeat`
- status: complete
- branch: `auto/roadmap-15-note-repeat`
- worktree: `.worktrees/roadmap-15-note-repeat`
- created: 2026-06-06T09:20:00Z
- landed-output-commit: `32a8eae014bab03562b730823233cd98960d9b20`
- current-output-state: landed final v1 output `32a8eae`; project integration
  fast-forwarded local `main` from
  `4ae588984c9e023b9c5ed3c2aeebba707d2a3492` to exact source commit
  `32a8eae014bab03562b730823233cd98960d9b20`, and
  `main...auto/roadmap-15-note-repeat` is `0 0`. The build-loop manifest now
  marks `build/note-repeat` terminal `complete`, so Note Repeat no longer
  consumes an ordinary active build slot.
- feature: `note-repeat`
- source PM loop: `pm/note-repeat`
- authoritative PM handoff:
  `docs/roadmap/note-repeat/implementation-handoff.md`
- promotion decision:
  `.meta/multipass/runtime/loops/project/decide/2026-06-06T09-20Z-note-repeat-build-promotion.md`

## Current Output State

Current exact output:

- HEAD: `32a8eae014bab03562b730823233cd98960d9b20`
- latest commit: `32a8eae fix(note-repeat): fit unsupported perform card label`
- worktree status: clean
- latest builder evidence:
  `.meta/multipass/runtime/loops/build/note-repeat/act/2026-06-07T02-28Z-phase-5-unsupported-card-text-fit-rework.md`
- latest observer evidence:
  `.meta/multipass/runtime/loops/build/note-repeat/observe/2026-06-07T03-07Z-visual-economy-phase-5-unsupported-card-text-fit.md`
- latest orientation:
  `.meta/multipass/runtime/loops/build/note-repeat/orient/2026-06-07T03-14Z-phase-5-exact-state-visual-economy-pass-orientation.md`

The current delta from prior fully reviewed Phase 5 commit
`2a2e3303b0ff084e75d828d6269979d6bf1e045f` is only
`Sources/UI/TracksMatrixView.swift`: unavailable Note Repeat perform-card state
now returns `No Clip` instead of the shared `UNAVAILABLE` label. Runtime
behavior, supported Note Repeat behavior, engine/session seams, persistence,
undo/redo, phrase/clip/scene/project state, audio, and MIDI paths are unchanged.

The intermediate `89cbc22e3a1217c121e398f03a0800ea4c8b2cc7`
`Unavailable` output is superseded by `32a8eae`.

## Intended User Outcome

The accepted Phase 5 surface gives the selected track a compact live
performance Note Repeat control:

- supported clip-backed selected tracks can engage and release momentary Note
  Repeat through `SequencerDocumentSession`;
- unsupported generator-backed targets remain unavailable safe no-ops;
- the perform card exposes `1/16`, `1/32`, and `1/64` interval selection for
  the next engagement;
- active state reads the engine runtime snapshot, including captured live
  interval;
- engage/release remains runtime-only and does not author phrase, clip, scene,
  project, undo, or redo state.

## Paired Evidence

Builder evidence for `32a8eae`:

- `.meta/multipass/runtime/loops/build/note-repeat/act/2026-06-07T02-28Z-phase-5-unsupported-card-text-fit-rework.md`
- `xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS,arch=arm64' GIT_COMMIT=32a8eae GIT_BRANCH=auto/roadmap-15-note-repeat build`
  passed with `** BUILD SUCCEEDED **`.
- exact unsupported visual artifacts:
  `.meta/multipass/runtime/loops/build/note-repeat/act/phase-5-note-repeat-perform-visual/unsupported.png`,
  `unsupported.status`, and `unsupported.command.env`.

Gate pairing:

| Gate | Evidence | Verdict | Current Use |
| --- | --- | --- | --- |
| architecture | `.meta/multipass/runtime/loops/build/note-repeat/observe/2026-06-07T00-54Z-architecture-review-phase-5-perform-surface-exact-state.md` | `pass` | inherited from `2a2e330`; current diff is label-only UI presentation |
| testing | `.meta/multipass/runtime/loops/build/note-repeat/observe/2026-06-07T00-53Z-testing-review-phase-5-perform-surface-exact-state.md` | `testing-pass` | inherited from `2a2e330`, paired with exact-state build pass at `32a8eae` |
| UX/IA | `.meta/multipass/runtime/loops/build/note-repeat/observe/2026-06-07T00-54Z-ux-ia-phase-5-perform-surface-exact-state.md` | `pass` | inherited from `2a2e330`; interaction model and surface placement unchanged |
| visual-economy | `.meta/multipass/runtime/loops/build/note-repeat/observe/2026-06-07T03-07Z-visual-economy-phase-5-unsupported-card-text-fit.md` | `pass` | exact-state review for corrected `No Clip` unsupported label |

Manual inherited-evidence read:

- source commit: `2a2e3303b0ff084e75d828d6269979d6bf1e045f`
- current commit: `32a8eae014bab03562b730823233cd98960d9b20`
- changed file: `Sources/UI/TracksMatrixView.swift`
- inherited gates: architecture, testing, UX/IA
- reason: the current exact diff only changes the unavailable Note Repeat
  label string branch and does not affect behavior, architecture, persistence,
  runtime, test fixtures, or interaction flow.

Visual-economy was not inherited from `2a2e330` because that source gate found
the unsupported label defect; it now passes at the exact corrected output.

## Remaining Evidence And Process Risk

No product rework is currently indicated. The remaining risk is integration
and process hygiene:

- lifecycle/capacity closeout evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-07T08-41Z-note-repeat-lifecycle-capacity-closeout.md`;
- there is no full new four-observer batch for `32a8eae`; this is acceptable
  for the label-only correction because the other gates are explicitly
  inherited and visual-economy has exact-state review;
- older batch metadata still says `status: open`; prefer named artifacts and
  run records over stale batch status;
- the full visual scenario has a known fixture/window-title mismatch
  (`Untitled` versus `Untitled.seqai`) and manual supported-active refresh did
  not complete. This is evidence-tooling risk for future fresh supported-state
  capture, not a blocker for the accepted unsupported-label correction;
- root `main` has broader project-level dirty-state concerns, so any
  integration route should respect current project integration hygiene.

Historical Note Repeat builder usage-limit failures are process evidence only;
the current output is clean and complete.

## Current Read

Lowest unmet pyramid layer: none for this build-loop's local lifecycle. Product
output is landed locally on `main` and build lifecycle is terminal.

Current next action kind: none for Note Repeat build-loop implementation,
review, integration, or capacity routing. Do not route builder rework or
another review unless there is a new exact-state source change or a fresh
post-merge product issue.

No systemic architecture escalation is indicated. Product-owner attention is
not needed.
