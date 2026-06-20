Sound source above the well is not needed

Screenshots:
- 19-track-detail-sound.png

RESOLVED 2026-06-20: Removed the redundant "SOUND SOURCE" eyebrow header above the sound-source well in the track Sound tab (Sources/UI/TrackSource/TrackRoutingTabContent.swift, soundSourceWell). The well (Add Sound Source card / MIDI editor / sampler) now sits directly under the tabs. Text-only removal, no behavior change. Verified via QA surface capture (19/19a-track-detail-sound PNGs): label gone in both populated and empty states.
