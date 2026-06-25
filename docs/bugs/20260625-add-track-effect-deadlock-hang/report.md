# Bug: adding an effect to a track hangs (graph-edit deadlock class)

Found: real-audio validation 2026-06-25 (post-revert build). Evidence:
add-effect-hang.sample (this dir).

Same family as the mute deadlock: the tick thread blocks on
SamplePlaybackEngine's lifecycle lock inside prepareTick while the main-thread
insert edit (applyTrackInsertsOnMain → reconnectTrackOutputOnMain, holding
graphLock + driving a live engine rebuild) runs. The captured sample for THIS
case is a heavy live-rebuild / AU-load stall more than a cleanly-captured
deadlock, but it is the same graph-edit-during-playback class and root cause
(see the mute-hang bug + task #47). Fix at root (don't hold locks across live
engine mutation); native vs AU insert both exercise the live-rebuild path.

Acceptance: add/remove an effect on a track during playback — no hang, no click.
