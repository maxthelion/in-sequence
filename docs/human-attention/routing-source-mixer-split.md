# Decide + verify: feature/routing-source-mixer-split

**Branch:** `feature/routing-source-mixer-split` (6 commits ahead of an old base;
only `3e619325` is substantive — splits the track ROUTING tab into a "Sound
Source" well + "Mixer & FX" well). **UI-only — does not touch `MainAudioGraph`.**

This is the natural home for the per-track **A / A+B / B scene-send selector**
(routing plan R4) — but the *audio* dependency for that selector is R0
(persistent send nodes), not this branch.

## Two blockers

1. **Stale + conflicted vs current main.** Main independently reworked the same
   routing surface (`7dcd7f0b` "Close QA capture-coverage gaps (routing editor)",
   `44efc6a3` "Remove redundant SOUND SOURCE label"). Real content conflicts in
   `TrackRoutingTabContent.swift`, `TrackDestinationEditor.swift`,
   `VisualScenarioCommandRunner.swift` (main rewrote heavily), plus
   `qa-surface-coverage.sh` + pbxproj. Needs a hand rebase reconciling intent,
   then `xcodegen`.
2. **Env-gated visual gate (needs you).** Code-complete, tests 21/0, arch/UX
   passed. The open gate is a visual-economy capture of the slicer routing tab
   (`22e-track-routing-tab-slicer-source.png`) that never completed because
   `SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION` was unset (TCC). After rebase, re-shoot
   `22d`/`22e` at the new tip (build badge must match) and rerun the mandatory
   adversarial critic.

## Decision for you
Given main already reworked this surface: **rebase-and-revive** vs **rebuild the
selector UI fresh on current main** (after R0 lands). Recommendation: defer until
R0 is in; then decide — a fresh rebuild on current main may be cheaper than the
conflict reconciliation.
