# Resolution: Mixer Tab Hang

Date: 2026-06-11 (foreman triage)
Status: fixed

Root-caused 2026-06-10 during the QA session: opening the Mixer page spun
one SwiftUI AttributeGraph transaction forever (a 3s process sample showed
1217/1225 main-thread samples in a single transaction). Two causes in
`MixerView.body`: a full `exportToProject()` call in a render path plus an
observable counter mutation during body evaluation. Fixed by introducing a
slice-scoped accessor for the view and marking the counter
`@ObservationIgnored`.

The underlying class — mutating `@Observable` state where Observation can
synchronously re-enter view bodies — recurred in the audio-input level
publisher and was fixed at the engine level on 2026-06-11 ("Never mutate
@Observable engine state while holding stateLock"). The class is now a
standing audit item in
`docs/code-health/2026-06-10-deep-dive-duplicates-bugs-races.md`.

Verified: mixer page opens and scrolls normally across all QA capture runs
since 2026-06-10 (capture 04).
