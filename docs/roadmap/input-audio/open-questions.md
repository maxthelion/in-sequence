# Input Audio — Open Questions

Raised during `write-architecture` on 2026-04-30.

Most of the twelve open questions from the UX review were resolved in
`architecture.md` without user input. Two decisions remain that have meaningful
product consequences and should not be guessed.

---

## Questions for the User

### 1. Maximum audio input tracks per session

The architecture proposes limiting v1 to **one audio input track** per session
(enforced in the UI by disabling the "create audio input track" action if one
already exists). The alternative is to support multiple audio input tracks from
the start, which requires a shared input distribution node in `MainAudioGraph`.

**Please confirm:** Is one audio input track per session sufficient for v1, or
should multiple audio input tracks be supported?

Implications:
- One track: simpler implementation, no input multiplexing, limit enforced in
  UI.
- Multiple tracks: requires shared input node, per-track channel routing, and
  more complex tap management from the start.

---

### 2. Loop playback timing (bar-locked vs. best-effort)

When the user switches to Loop mode after recording, should the loop begin
playing back:
- **(a) Immediately** (best-effort, starts as soon as the mode toggle is
  tapped, not locked to the bar boundary), or
- **(b) At the next bar boundary** (Octatrack-style, so the loop is always
  heard in musical phase with the sequence)?

Implications:
- Immediate start is simpler (no quantization needed for playback start, just
  for recording start).
- Bar-locked start requires the loop playback to be quantized using the same
  `TickClock` bar-boundary detection used for the ARM countdown. This is more
  complex but gives a tighter live-performance feel.

---

## Resolved questions (documented in `architecture.md` — no user input needed)

| UX review Q | Resolution |
|---|---|
| Q1 Engine restart on device switch | Short rewire (~1 s stop/restart), not full teardown. Failure path required in spec. |
| Q2 Independent vs. aggregate device | Independent input/output device selection confirmed. |
| Q3 Sample rate / buffer size | Deferred to later milestone. |
| Q4 Missing device at next launch | Silent fallback to system default + banner in Preferences. |
| Q5 Engine device-switch failure state | Error state required in spec (fall back to previous UID). |
| Q6 Step-pattern grid | No step grid on audio input track in v1. |
| Q7 Live input routing in Loop mode | Gated: only one signal path (live or loop) reaches the mixer at a time. |
| Q8 Overdub vs. destructive replace | Destructive replace, no confirmation dialog, for v1. |
| Q9 Real-time waveform during recording | Real-time streamed fill using running-max bucket array. |
| Q10 BPM change after recording | Out of scope; loop plays at original duration. Explicitly excluded in spec. |
| Q11 Per-track hardware channel selector | In scope; persisted as `inputChannel` on `StepSequenceTrack`. |
| Q12 Navigation away while recording | Recording continues; track list shows pulsing indicator on audio input track card. |
