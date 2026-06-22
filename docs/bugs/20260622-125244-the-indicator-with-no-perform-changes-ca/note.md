The indicator with no perform changes can go. Instead, capture and discard should only be available when it perform mode. They should be disabled if no captures, and become green when changes are made. Likewise, moment and latch are only useful in perform mode and should be otherwise hidden. But I don't want the buttons moving around horizontally. So perhaps perform is the rightmost optiion.

---
RESOLVED 2026-06-22: removed the "NO PERFORM CHANGES" indicator; Capture/Discard gated to perform mode + dirty state (green via isDirty when changes staged); MOM/LATCH hidden outside perform; Perform is rightmost and the bar no longer shifts horizontally.
VERIFIED — independent agent PASS (B1 no-indicator, B2 mom/latch gating, B3 perform rightmost, B4 capture/discard present); evidence: 06-phrase-scenes-perform.png (perform) + 08-phrase-layers-pattern.png (non-perform). Green-on-changes covered by updated PhraseMatrixLayoutPresentationTests (not fixture-capturable).
