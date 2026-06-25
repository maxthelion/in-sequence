observer to root out the wrong shape left behind

Can you look at the gate for the legacy path and generalize that as a pattern for an observer to look for. It should have the mission of rooting out these places where the wrong shape has been left behind.

This came out of the audio routing work: I want to check that the new stuff doesn't leave the old code behind as a sort of fallback. We want the clean version only.

Concrete example to generalize from: the `offlineBounce` gate in `MainAudioGraph.installSendBusesLocked` (commit 47ec199a) — a mode flag (`manualRenderingMode == .offline`) that re-introduces the old `engine.stop()/prepare()/start()` shape the R2 refactor had removed, kept behind the gate while the other branch uses the new live-reconnect shape.
