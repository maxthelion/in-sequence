# Resolution — branch fix/ui-consistency-bugs

Engine capture verified working end-to-end with new tests
(`Tests/SequencerAITests/Engine/ClipHistoryLiveCaptureTests.swift`): a playing
generator populates the rolling capture buffer, the view model surfaces it,
and capture resumes after audition stops.

The user-visible failure was the silent no-ticks case: with the transport
stopped, nothing records and the UI said "Waiting for live notes." forever.
The empty state is now transport-aware: "Press play to record live history."
when stopped.

Note: capture is intentionally paused while auditioning a history selection
(existing engine test asserts this).
