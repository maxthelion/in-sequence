# Bug: routing changes hard-disconnect sounding nodes (clicks, no ramp)

Found: adversarial review 2026-06-25.

reconnectTrackOutputOnMain does a bare `engine.disconnectNodeOutput(source)`
(MainAudioGraph ~:1596) on a possibly-sounding track, called live from
connectTrackOutput (bus reassign, R1), applyTrackInsertsOnMain (insert change,
R2), install*Buses. The fixed-superset plan's central invariant — "nothing
sounding is ever disconnected; ramp to silence first; equal-power gain ramps
~5-15ms" — is unimplemented (zero ramp logic in the file; in-code comment admits
it's a "follow-up"). So live bus-reassign / insert change clicks.

Fix: implement equal-power ramps; ramp to silence before any disconnect, cut on
silence, ramp back. Task #48.
