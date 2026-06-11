# Foreman state

Last tick: 2026-06-11 (seeded manually during setup; this session acted as
the trial tick).

## In flight

- `feature/drum-kits-and-templates` (worktree
  `.worktrees/drum-kits-and-templates`): COMPLETE and green (1295/0 with
  the two machine-state CoreAudio tests excluded), main merged in. Waiting
  on Max's look before merge — see attention. Capture evidence for the new
  kit matrix exists in the worktree's capture dir and the served gallery
  under /feature/.
- Multipass build loops continue independently; do not touch their
  worktrees.

## Next tick should check first

- Has Max approved the kits/templates merge? If yes in `full` autonomy:
  run `.foreman/checklists/feature-merge.md` and land it.
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
