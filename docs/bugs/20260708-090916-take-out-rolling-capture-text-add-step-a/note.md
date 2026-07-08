Take out Rolling capture text. Add step and bar markers to the waveform. Put a playhead on it.

Screenshots:
- 27c-audio-playback.png

Capture references:
- 27c-audio-playback.png (in-sequence/qa-surface-coverage; main @ 53e42ea6; run 20260707-215434-in-sequence-qa-surface-coverage-main-53e42ea6; c20abded9ae422ec505d409400612961)

Status: RESOLVED; corrected after gallery review by adding a readable top beat ruler to the audio playback waveform (bar labels plus quarter-beat labels such as 1.2/1.4) and stronger bar/quarter guide lines. Verified with focused qa-surface-coverage capture 27c-audio-playback.

Follow-up: normalized shared waveform bucket fitting so sparse sampler/slicer/audio buckets resample to the current drawable width, preserving an approximately 3 px bar / 1 px gap rhythm on resize. Verified with focused captures 27c-audio-playback, 23e-track-slicer-slice-tab, and 19-track-sampler-sound-populated.
