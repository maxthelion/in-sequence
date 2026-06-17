# input-audio

- loop: `build/input-audio`
- status: complete
- branch: `auto/roadmap-7-input-audio`
- worktree: `.worktrees/roadmap-7-input-audio`
- created: 2026-06-03T05:15:28.464Z
- last-oriented: 2026-06-04T07:28Z
- last-decided: 2026-06-04T07:32Z
- previous-fully-reviewed-commit: `8474975c43163813062954ae519b63e1c72dbf51`
- current-fully-reviewed-commit: `b00bac98a299ee081c72b76563ce4e39ef884057`
- previous-output-commit: `8474975c43163813062954ae519b63e1c72dbf51`
- current-output-commit: `b00bac98a299ee081c72b76563ce4e39ef884057`
- current-output-state: landed final v1 output `b00bac9`; exact architecture,
  testing/build, UX/IA, and visual-economy observer gates all passed for this
  commit; project integration landed the candidate on local `main` by
  fast-forward and the build-loop lifecycle is terminal `complete`

This is the durable build-loop summary. Transient inboxes, runs, and evidence
live under `.meta/multipass/runtime/loops/build/input-audio/`.

## Current Disposition

Input Audio final v1 output
`b00bac98a299ee081c72b76563ce4e39ef884057` landed on local `main` by
fast-forward. Project integration evidence is recorded at
`.meta/multipass/runtime/loops/project/act/2026-06-04T08-07Z-input-audio-b00bac9-landed.md`.

Direct closeout checks confirm `main` and `auto/roadmap-7-input-audio` both
resolve to `b00bac9`, `auto/roadmap-7-input-audio` is contained by `main`, and
`main...auto/roadmap-7-input-audio` is `0 0`. The public build-loop registry
and loop-local manifest now mark `build/input-audio` terminal `complete`, so it
no longer consumes active build-loop capacity.

No product rework, merge, push, worktree deletion, review routing, or
product-owner action is implied by this lifecycle closeout.

## Current Orientation

Latest orientation:

`.meta/multipass/runtime/loops/build/input-audio/orient/2026-06-04T07-28Z-final-v1-b00bac9-batch-passed-merge-candidate.md`

The feature worktree `.worktrees/roadmap-7-input-audio` on
`auto/roadmap-7-input-audio` has `HEAD` at:

`b00bac98a299ee081c72b76563ce4e39ef884057`

`b00bac9 Fix sample send activation routing`

Direct worktree status is clean:

```text
## auto/roadmap-7-input-audio
```

Disposition:

`landed_complete`

Lowest unmet layer:

`none_for_build_loop_lifecycle`

Latest decision:

`.meta/multipass/runtime/loops/build/input-audio/decide/2026-06-04T07-32Z-b00bac9-feature-complete-merge-candidate.md`

Next action kind:

`none_for_input_audio_build_loop`

Product-owner attention:

`not_needed`

## Fresh Builder Evidence

Builder request:

`.meta/multipass/runtime/inbox/done/2026-06-04T07-03-31-189Z-builder.md`

Compact run record:

`.meta/multipass/runtime/loops/build/input-audio/runs/act/builder/2026-06-04T07-03-31-189Z-builder.json`

Builder final:

`.meta/multipass/runtime/runs/actors/builder/2026-06-04T07-03-31-189Z-builder.final.md`

Loop-local act evidence:

`.meta/multipass/runtime/loops/build/input-audio/act/2026-06-04T07-20Z-final-v1-evidence-closure-b00bac9.md`

Runtime screenshot/status evidence:

`.meta/multipass/runtime/loops/build/input-audio/act/2026-06-04T07-20Z-final-v1-input-audio-runtime/`

Broad app-surface screenshots:

`.meta/multipass/runtime/loops/build/input-audio/act/2026-06-04T07-20Z-final-v1-app-surfaces/`

Builder-reported current-state checks:

- pre-fix focused repro failed
  `SamplePlaybackEngineFilterWiringTests.test_sampleTrackSendTapRoutesAfterSamplerFilter`;
- post-fix focused send-routing test passed;
- `SamplePlaybackEngineFilterWiringTests` passed, 8 tests, 0 failures;
- `MainAudioGraphTests` plus focused audio-input routing tests passed, 16
  tests, 0 failures;
- final broad selected regression run passed, 189 tests, 1 known skip, 0
  failures;
- final Input Audio runtime scenario passed for live, recording, completed,
  playback, loop-empty, invalid-route, and recording-away states;
- `xcodebuild -list`, `plutil -lint`, visual script `bash -n`, and
  `git diff --check` passed.

## Current Output Scope

`b00bac9` changes one production file relative to `8474975`:

- `Sources/Audio/MainAudioGraph.swift`

The change makes `MainAudioGraph.setTrackSendLevels` reconnect track output
routing when send levels move between inactive and active states. This keeps
the cheap gain-only path when send nodes already exist and sends remain active.

## Exact-State Gate Pairing

Batch manifest:

`.meta/multipass/runtime/loops/build/input-audio/observe/batches/b00bac98a299ee081c72b76563ce4e39ef884057/batch.yaml`

The batch manifest still says `status: open`, but all four expected observer
requests are in `.meta/multipass/runtime/inbox/done/`, compact run records report
`status: complete`, and each observer wrote a loop-local pass artifact paired
to exact commit `b00bac9`. Treat the open batch status as stale runtime
metadata, not a missing observer.

| Gate | State | Evidence |
| --- | --- | --- |
| Architecture | pass | `.meta/multipass/runtime/loops/build/input-audio/observe/2026-06-04T07-21Z-architecture-review-final-v1-b00bac9-pass.md` |
| Testing/build | pass | `.meta/multipass/runtime/loops/build/input-audio/observe/2026-06-04T07-24Z-testing-review-final-v1-b00bac9-pass.md` |
| UX/IA | pass | `.meta/multipass/runtime/loops/build/input-audio/observe/2026-06-04T07-22Z-ux-ia-review-final-v1-b00bac9-pass.md` |
| Visual economy | pass | `.meta/multipass/runtime/loops/build/input-audio/observe/2026-06-04T07-24Z-visual-economy-final-v1-b00bac9-pass.md` |

No inherited gate credit is needed or accepted for `b00bac9`; all four gates
have fresh exact-state pass artifacts.

Advisory scoped-gate invalidation was rerun at 2026-06-04T07:27Z against
`8474975..HEAD`. It reported current commit `b00bac9`, changed file
`Sources/Audio/MainAudioGraph.swift`, no configured scope hints, and
full-review-default / exact-state-required impact. The exact-state review batch
resolves that advisory.

## Gate Interpretation

Architecture passed. The graph ownership boundary remains coherent: authored
send values stay in document/session state, while transient AVAudioEngine
fanout nodes, send gain nodes, and dry/send connections stay in
`MainAudioGraph`.

Testing/build passed. The observer reran `xcodebuild -list` plus focused
graph/sample routing tests, with 22 tests and 0 failures, and accepted the
builder's broader selected regression evidence for the narrow runtime graph
delta.

UX/IA passed. The Input Audio workflow remains legible across live input,
recording, completed loop, loop playback, loop-empty silence, invalid route,
and recording-away states.

Visual economy passed. The targeted runtime screenshots/status sidecars are
truthful and proportionate for the Input Audio surface. Broad app-surface
fallback captures remain weak and should not be over-credited, but they do not
block this scoped visual gate.

## Residual Evidence Risk

The build-loop product gates are passed, with these residual caveats for
integration:

- no physical audio input device produced the captured signal in the final
  pass;
- no manual speaker-listening pass was performed;
- deterministic runtime/status automation was accepted by observers as the
  substitute for this build-loop gate, not as hardware or acoustic proof;
- broad app-surface fallback screenshots are weak and include navigation
  failures/mislabeled workspace evidence;
- final Preferences missing-device/failure screenshots were not recaptured at
  `b00bac9`, though no Preferences UI changed in this commit;
- project integration and focused landed-state checks are now recorded at
  `.meta/multipass/runtime/loops/project/act/2026-06-04T08-07Z-input-audio-b00bac9-landed.md`.

Product-owner attention is not needed.

## Merge-Readiness Context

Fresh advisory preflight from root refs:

- `git rev-list --left-right --count main...auto/roadmap-7-input-audio`
  reports `0 26`.
- `git merge-tree --write-tree main auto/roadmap-7-input-audio` produced tree
  `28a5b2cd88aceec8e5a67497938cef160f2892d8` with no conflict output.
- `git diff --check main...auto/roadmap-7-input-audio` passed with no output.

Root `main` itself is dirty with pre-existing coordination-state and unrelated
product files, so this is advisory merge-readiness context against refs, not a
landed-state integration result.

## Missing Evidence

Missing before build-loop candidate acceptance:

- none for the unchanged exact output `b00bac9`; the expected exact-state
  architecture, testing/build, UX/IA, and visual-economy gates have passed,
  and the build decider accepted it as the build-loop merge candidate.

Missing before landed completion:

- none for unchanged `b00bac9`; project integration and focused landed-state
  checks are recorded in
  `.meta/multipass/runtime/loops/project/act/2026-06-04T08-07Z-input-audio-b00bac9-landed.md`.

## Prior Failure Context

Earlier recorded-loop builder attempts were blocked by `SIGTERM` /
`usage_rate_limit` and left staged partial work:

- `.meta/multipass/runtime/inbox/blocked/2026-06-04T06-09-25-105Z-builder.md`
- `.meta/multipass/runtime/inbox/blocked/2026-06-04T06-22-45-943Z-Input-Audio-recorded-loop-workflow-builder-recovery.md`
- `.meta/multipass/runtime/runs/actors/builder/2026-06-04T06-09-25-105Z-builder.failure.md`
- `.meta/multipass/runtime/runs/actors/builder/2026-06-04T06-22-45-943Z-Input-Audio-recorded-loop-workflow-builder-recovery.failure.md`

Those failures are process history, not the current output state. The current
worktree is clean at review-passed `b00bac9`.
