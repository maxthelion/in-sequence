# Attention ledger

Items genuinely needing Max, ranked. Each says what it unlocks.

1. **Merge call: `feature/drum-kits-and-templates`.** Gates are green
   (1295 tests, capture evidence, intent checked). A yes unlocks the
   library-pools work (id 26) that shelves these asset types. Recommended:
   poke the creation modal by hand first — it has no capture rows yet.
2. **Audio-input hardware validation.** Needs your interface and ears:
   channel selection on the 24ch device, arm/record at next bar, levels.
   Unlocks closing the input-audio feedback loop for good.
3. **swift-atomics dependency decision.** The in-house atomics use
   deprecated OSAtomic; the modern replacement needs either macOS 15
   (target is 14) or adding the swift-atomics package. Low urgency.
