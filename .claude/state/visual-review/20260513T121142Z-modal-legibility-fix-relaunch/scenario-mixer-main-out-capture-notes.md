# Mixer Main Out Scenario Evidence

The scenario opens a new document, navigates to the Mixer workspace, drives
the Master Out meter readout, moves the combined fader/meter control high and
low, restores it near unity, then clears the clip latch.

For deterministic visual evidence, the visual-review environment points new
documents at `docs/roadmap/mixer-main-out/fixtures/mixer-main-out-live-meter.seqai`.
The scenario uses the app's visual command hook to feed the production
`MasterMeterPublisher` while the app remains on the real Mixer/Master Out
surface. This avoids relying on fragile coordinate clicks or unavailable
transport/audio input during screenshot capture.

Status from this script run: completed normal/live-meter/fader-high/clipped/fader-low/restored/clipped-cleared captures.

If the run stops before all screenshots are written, inspect
`scenario-actions.log`, the visual command status file, and `app.stderr.log`
in the same capture folder.
