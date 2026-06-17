The AU plug-in lists (instruments AND effects) only refresh when the app
launches. A plug-in installed while the app is running does not appear
until you quit and relaunch — confusing friction right after installing
something (hit live with TDR Kotelnikov, an aufx effect: installed, not
in the FX list, only showed after a relaunch).

Cause (verified):
- `AudioInstrumentChoiceCache` and `AudioEffectChoiceCache`
  (Sources/Audio/) each warm a single process-global scan of
  `AVAudioUnitComponentManager.shared().components(matching:)` at app
  launch and hold it for the lifetime of the process. The doc comment
  even states "new plug-in installs require relaunching the app." The
  one-launch-warm exists for good reason (the first scan validates every
  installed AU and can block for seconds), but it leaves no way to pick
  up a newly-installed plug-in without a relaunch.

Not a type-filter problem: the effects scan matches both
`kAudioUnitType_Effect` and `kAudioUnitType_MusicEffect`, so an aufx
effect like Kotelnikov IS enumerated — it's purely the launch-time cache
that hid it. (The instrument list is MusicDevice-only by design; effects
correctly live in the Send-bus / Master FX insert picker, not on tracks.)

Desired:
- A "Rescan plug-ins" action (e.g. in the FX insert picker and/or the
  instrument picker, or a small settings/menu item) that invalidates
  both caches and re-warms them off the main thread, so a freshly
  installed AU appears without relaunching.
- Keep the scan off the main thread (it's slow / blocking) — reuse the
  existing background-warm path; show a brief "scanning…" state rather
  than freezing the picker.
- Invalidating one cache should be cheap and safe to call repeatedly.

Acceptance check:
- Install a new AU effect while the app is running, trigger "Rescan
  plug-ins", and it appears in the FX insert picker without a relaunch.
- The rescan does not block/freeze the UI while it runs.
- Instruments behave the same way for a newly-installed aumu instrument.
