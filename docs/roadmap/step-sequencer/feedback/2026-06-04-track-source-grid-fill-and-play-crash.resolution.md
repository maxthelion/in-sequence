# Resolution
Date: 2026-06-11 (foreman triage). Status: crash fixed; layout in sweep.
The play crash class (AVAudioPlayerNode.play throwing on a
stopped/reconfiguring engine) was eliminated 2026-06-10/11: playability
checks plus an ObjC exception catcher on every play()/scheduleBuffer site —
a failed start drops the trigger and traces instead of killing the app
(see docs/code-health/2026-06-10 report and the SamplePlaybackEngine /
MainAudioGraph guard commits). The cells-don't-fill-the-editor concern is
part of the 2026-06-11 wasted-space bug reports being fixed in the
feature/ux-bug-sweep branch.
