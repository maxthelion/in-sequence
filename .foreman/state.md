# Foreman state

Last tick: 2026-06-11 (seeded manually during setup; this session acted as
the trial tick).

## In flight

- kits/templates MERGED to main (Max approved, gate green, 1298 tests
  post-merge). Worktree and branch now cleaned up.
- The 2026-06-11 morning bug reports: RESOLVED by the ux-bug-sweep merge
  (158bf031) — each has a resolution.md. Visual verification against
  captures still pending console unlock.
- The two intent-drift feedback files are now DISPATCHED (no longer
  pending a lens): drift verified real on main 2026-06-11 (StepGridView
  still hard-codes isSelected:false; ClipStepInspectorSheet still the
  inspect path; clip-history multipass loop is status:complete so its
  post-merge feedback is foreman-owned).
  - Agent: feature/track-source-step-grid — RESUMED (post-limit) with a
    continue-the-dirty-work brief; instructed to commit incrementally.
  - Agent: feature/clip-history-corrections — RESUMED the same way.
- Codex interim work VERIFIED AND LANDED on main as e56c5f75 (full suite
  green first): BuildIdentity surfaced in top bar/logs (resolves the
  observability visible-build-identity feedback — resolution written;
  multipass loop's parallel partial work in
  .worktrees/roadmap-21-observability-log-issues needs reconciling by
  its decider), master-bus unity pass-through, sample-accurate voice
  starts, master render test coverage.
- Max's five 2026-06-11 afternoon bugs, triaged. Dispatch queue (max two
  concurrent agents; pop when a slot frees):
  1. small-UI sweep — 143510 (phrase left box: drop bar/repeat labels,
     align cell heights, contain right-side controls) + 144448 (perform
     rotaries 4-per-row, dedupe "assign" labels) + 145433 (add-track
     cell same height/no text; layer changer same as perform mode).
  2. mixer overhaul — 143027 (his detailed layout rulings: levels on all
     strips, pan BELOW volume as side-to-side element [overrides the
     review doc's rotary-pan idea], sends grouped next to master,
     consistent fx slot, small uniform titles, in-place send rotaries,
     solo-banner misalignment, single add-bus control) +
     docs/bugs/2026-06-10-mixer-ux-review.md + roadmap 29 levels.
  3. flat-UI variant — 142049: flatter, less opacity, per his reference
     screenshot; build as a TRY-IT branch (feature/flat-ui-variant), do
     NOT merge without Max's review — he asked for a variant to try.
- QUEUED (next free build slot): mixer overhaul slice combining
  docs/bugs/2026-06-10-mixer-ux-review.md (shared strip scaffold, pan
  rotaries, master overlay occlusion, dB convergence) with roadmap item
  29 mixer-channel-levels (all strips metered, master as template).
- build-identity feedback remains with its active multipass loop
  (observability-log-issues).
- Multipass build loops continue independently; do not touch their
  worktrees.

## Foreman tick 2026-06-11 ~12:23 (partial — interactive session active)

Max is mid hardware-validation of audio input in this session; build- and
capture-contending triage deferred per resource rules. Done this tick:
resolutions written for mixer-tab-hang and fill-preview-placement feedback
(both verified fixed). Classified the rest:

- build-identity feedback: ACTIVE multipass work (observability loop) —
  not the foreman's to resolve; leave its fingerprint entry pending.
- 9 bug reports (UI polish: wasted space, card noise, single/inherit
  bars, destination panel, sample player, phrase title) + 11 remaining
  feedback files (clip-history x3, layer-matrix-shape, scene/scenes/step
  prototypes feedback, track-source x2, multiselect-latch x2): NEXT
  non-contended tick — most bug reports look like one ux-canon sweep
  (rules 1/3/10) over the track page; batch as patterns.
- feature/drum-kits-and-templates local branch is merged but deletion is
  permission-gated — Max: `git branch -d feature/drum-kits-and-templates`.

## Next tick should check first

- Whether the interactive session has ended (then run the deferred
  triage above, including the full-suite gate over the audio-input
  changes).
- The eight 2026-06-11 bug reports (triage rules apply).
- New entries in `docs/bugs/` (the bug app writes here continuously).
- The two real-hardware CoreAudio tests
  (`MainAudioGraphDeviceSwitchTests`, the input-wiring engine test) pass
  only when coreaudiod is healthy; if they fail with the kAUStartIO/990s
  signature, that is machine state, not code.

## Autonomous phase (Max away, 2026-06-11 ~12:45)

Standing instruction: clear all intents and bugs; park ear-dependent
audio validation; master-render-to-file shipped (graph+engine+tests).

In flight:
- feature/ux-bug-sweep MERGED to main (158bf031, all 9 bug reports
  resolved with resolution.md files). Post-merge on main: xcodegen run,
  Info.plist keys intact, suite green except
  TickClockTests.test_tick_intervals_match_expected_bpm — wall-clock
  flake under load, passes in isolation (rerun verified).
- feature/library-pools MERGED to main (fast-forward to 82ba0289 after
  merging main into the branch; gate suite green on the identical tree
  in the worktree, evidence inherited exact-commit). LibraryWorkspaceView
  conflict resolved toward the branch's real library page.
- Capture evidence for both merges queued for next console unlock
  (qa-surface-coverage rows 01-42 incl. new Library rows 40-42 + gallery
  refresh + ux-canon review). Console checked locked at 14:00.
- Worktrees .worktrees/bug-sweep and .worktrees/library-pools removed;
  branches feature/ux-bug-sweep, feature/library-pools and
  feature/drum-kits-and-templates deleted (all fully merged).

Parked for Max's ears (attention list): buffer playback audibility
(self-healing retry landed but unheard), input monitoring through EVO16,
record-length click (trace added, needs one repro).

Done this phase: intents inbox processed (roadmap items 28, 29); master
render to file landed with tests; 9 stale feedback resolutions (2 left
for the intent-drift lens: step-sequencer track-source-gap, clip-history
live-buffer-save-arm).

CAUTION (self): stage explicit paths only — `git add docs/roadmap` swept
~30 untracked PM artifacts into 2dd2cb5c (kept; they are durable docs).

## Known machine-state hazards

- TCC mic prompts re-arm on every rebuild (ad-hoc signing). The capture
  harness is hermetic against this; interactive use prompts only via the
  explicit Enable Microphone button.
- Capture runs require an unlocked console; coordinate via the unlock
  check, never retry blindly.
- `Sources/Resources/Info.plist` loses keys to xcodegen churn; diff
  against HEAD after any generate/merge.
