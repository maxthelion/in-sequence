## STATUS: RESOLVED (triaged 2026-06-26, audio-routing-cleanup) — already implemented + committed

A runtime AU rescan is fully implemented and committed on this branch
(`54d46ae7 Re-integrate AU plugin rescan onto current main`, plus
`9cd7cd13 Dedupe mixer/phrase studio UI helpers`). Nothing further was needed;
the working tree is clean for all Bug-B files.

What ships:
- `AudioInstrumentChoiceCache` and `AudioEffectChoiceCache`
  (Sources/Audio/AudioInstrumentChoiceCache.swift, Sources/Audio/AudioEffectChoice.swift)
  each gained `beginRescanIfNeeded()`, `rescanChoices()`, and a non-blocking
  `currentChoicesIfAvailable` snapshot, on top of the launch `beginWarmingIfNeeded()`.
  `performScan()` RE-QUERIES `AVAudioUnitComponentManager.shared().components(matching:)`
  on every call, so a rescan re-enumerates (effects match both
  `kAudioUnitType_Effect` and `kAudioUnitType_MusicEffect`). The rescan runs on a
  background `userInitiated` queue; a repeated request while scanning is a cheap
  no-op (`false`); the previous list stays visible during the scan.
- `EngineController.rescanAudioPluginChoices()` (Sources/Engine/EngineController.swift)
  drives both caches off-main via the injectable `audioPluginChoiceRescanner`,
  publishes `.scanning` → `.ready(instrumentCount:effectCount:)` to main, and
  ignores re-entrant presses. `availableAudioEffects` falls back to the live
  snapshot while scanning so the picker never blinks empty.
- UI affordance: `StudioPluginRescanHeader` (Sources/UI/Mixer/AUEffectPickerList.swift)
  — a scan-state line + "Rescan" button — is mounted in the AU effect picker
  (AUEffectPickerList) and the add-destination/instrument sheet
  (Sources/UI/TrackDestination/AddDestinationSheet.swift), calling
  `engineController.rescanAudioPluginChoices()`.

Tests (all pass, 2026-06-26):
- Tests/SequencerAITests/Audio/AudioInstrumentChoicesCacheTests.swift — rescan
  replaces cached instrument AND effect choices, performs exactly one fresh scan
  per rescan, preserves the previous list (incl. large lists) while scanning,
  and treats repeated in-flight rescans as no-ops.
- Tests/SequencerAITests/Engine/EngineControllerTests.swift
  `test_rescanAudioPluginChoicesPublishesScanningThenReadyCountsAndIgnoresRepeat`
  — publishes scanning→ready counts and ignores a repeat.

Residual (HUMAN visual check — unattended-blocked): installing a brand-new AU
while the app runs and confirming it appears in the picker after "Rescan" without
relaunch, and confirming the UI does not freeze during the scan. Enumeration is
headless-safe, but verifying a freshly-installed AU surfaces (and that AU
INSTANTIATION still works) needs a present human (macOS permission tier). Also
note: the rescan re-queries the component manager but does not subscribe to
`AVAudioUnitComponentManager`'s registration-change notification — in practice
`components(matching:)` picks up newly-registered AUs, but that is the specific
thing the human pass should confirm.

---

## Original report

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

Status: RESOLVED — already implemented (54d46ae7 rescan + Rescan button, 11 tests)
