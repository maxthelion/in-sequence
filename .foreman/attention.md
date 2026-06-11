# Attention ledger

Items genuinely needing Max, ranked. Each says what it unlocks.

1. **Audio-input hardware validation.** Needs your interface and ears:
   channel selection on the 24ch device, arm/record at next bar, levels.
   Unlocks closing the input-audio feedback loop for good.
2. **Worktree cleanup (one command).** The merged kits/templates worktree
   holds untracked derived data, so removing it needs force:
   `git worktree remove .worktrees/drum-kits-and-templates --force`
3. **swift-atomics dependency decision.** The in-house atomics use
   deprecated OSAtomic; the modern replacement needs either macOS 15
   (target is 14) or adding the swift-atomics package. Low urgency.
