# Foreman state

Last tick: 2026-06-11 (seeded manually during setup; this session acted as
the trial tick).

## In flight

- kits/templates MERGED to main (Max approved, gate green, 1298 tests
  post-merge). Worktree awaits force-removal by Max (attention item 2).
- Eight unprocessed bug reports from 2026-06-11 morning in `docs/bugs/`
  (phrase matrix noise, wasted space, single/inherit bars, destination
  panel, sample player) — next tick's primary triage queue. Several look
  like ux-canon rules 1/3/10 violations; sweep as patterns, not instances.
- Fourteen stale `docs/roadmap/*/feedback/` files lack resolutions; at
  least two (mixer-tab-hang, build-identity) are already fixed in
  substance and only need resolution notes written.
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

## Known machine-state hazards

- TCC mic prompts re-arm on every rebuild (ad-hoc signing). The capture
  harness is hermetic against this; interactive use prompts only via the
  explicit Enable Microphone button.
- Capture runs require an unlocked console; coordinate via the unlock
  check, never retry blindly.
- `Sources/Resources/Info.plist` loses keys to xcodegen churn; diff
  against HEAD after any generate/merge.
