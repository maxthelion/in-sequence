# Input Audio: Channel Selection + Resample Source — Design

Date: 2026-06-10. Status: designed, needs hardware-in-the-loop implementation.

## A. Hardware channel selection (owner: "select which channels we want")

Smallest schema change that reaches all 24 inputs:

- Add `inputChannelOffset: Int = 0` to `StepSequenceTrack` (Codable default
  0 → old documents decode unchanged; no enum migration).
- Semantics: the existing Mono 1 / Mono 2 / Stereo selection operates on the
  *pair at the offset* — Mono 1 = device channel offset+1, Mono 2 =
  offset+2, Stereo = the pair. UI adds an "Inputs 1-2 / 3-4 / … / 23-24"
  pair picker next to the existing selector, populated from
  `EngineController.audioInputAvailableChannels`.
- Route state: available iff `offset + requiredChannelCount <=
  availableChannels`.
- Graph: select channels via the input unit's channel map —
  `engine.inputNode.auAudioUnit.channelMap = [offset, offset+1]` (nil for
  offset 0). This is the modern AUAudioUnit API; needs validation against a
  real multi-channel interface because inputNode channel-map behavior
  varies by device/driver. NOTE: verify what today's Mono 2 actually does
  on hardware first — `reconnectAudioInputSourceOnMain` connects the full
  input format to the host mixer and no channel extraction is visible in
  the graph code, so Mono 1/Mono 2 may currently be cosmetic.

Implementation must be validated live (arm, record, monitor on channels
beyond 1-2). Recommend an interactive session with the 24-ch interface
attached.

## B. Resample from another track's output

`MainAudioGraph.AudioInputMonitorSource` is a clean enum (input / loop /
silent). Add `.trackOutput(trackID: UUID)`:

- `reconnectAudioInputSourceOnMain` connects the source track's playback
  sink output mixer into the input host's `outputMixer` (needs AVAudioEngine
  fan-out: one node → original destination + the input host, via
  `connect(_:to: [AVAudioConnectionPoint])`).
- The capture tap already sits on the host's `outputMixer`, so recording
  and the rolling waveform follow the new source with zero capture changes.
- UI: the Monitor selector grows a "Track" option with a source-track
  picker (any track with an audio sink).
- Recorded resamples should land in the global library per the Library
  Pools design (item 26), tagged with the source track.

## Interlocks

- Library Pools (item 26): recordings → global library.
- The kit-matrix rework feedback remains separately unactioned.
