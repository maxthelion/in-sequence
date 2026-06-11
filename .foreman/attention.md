# Attention ledger

Items genuinely needing Max, ranked. Each says what it unlocks.

1. **Audio-input hardware validation.** Needs your interface and ears:
   buffer playback audibility, input monitoring through the EVO16,
   record-length stuck-on-2-bars repro (trace armed:
   `setAudioInputRecordBarLength bars=`), channel selection on the 24ch
   device. Unlocks closing the input-audio feedback loop for good.
2. **Unlock the screen once** so the queued QA capture run (rows 01-42,
   including the new Library page rows 40-42) and gallery refresh can
   verify the ux-bug-sweep and library-pools merges visually.
3. **swift-atomics dependency decision.** The in-house atomics use
   deprecated OSAtomic; the modern replacement needs either macOS 15
   (target is 14) or adding the swift-atomics package. Low urgency.

Resolved since last review: kits/templates worktree already removed;
feature branch deletions (drum-kits-and-templates, ux-bug-sweep,
library-pools) completed by foreman 2026-06-11 — no longer gated.
