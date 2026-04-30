---
verdict: accepted
selected_prototype: 02-audio-input-track-page.html
reviewed: 2026-04-30
prototypes_reviewed:
  - prototypes/01-audio-preferences.html
  - prototypes/02-audio-input-track-page.html
feedback_applied: []
---

# Input Audio UX Review — 2026-04-30

## Context

Two prototypes cover the full feature scope. Prototype 01 addresses Story 1
(audio interface selection in preferences). Prototype 02 covers Stories 2–7
(the audio input track workspace: create track, record loop, choose bar length,
quantized arm, input/loop toggle, waveform). There were no prior review cycles
and no feedback files to apply. This is a first-pass review.

---

## Checklist Results

The checklist columns below use: Pass / Fail / Partial / N/A.

| Criterion | 01 — Prefs | 02 — Track Page |
|---|---|---|
| Single-file, no build steps | Pass | Pass |
| Monochrome base, semantic color only | Pass | Pass |
| Stub regions clearly marked | Pass | Pass |
| Real interactions on primary path | Pass | Pass |
| Fixture data is adversarial / varied | Pass | Pass |
| Interaction budget stated and verified | Pass | Pass |
| Variants are strategically different | N/A (single variant) | N/A (single variant) |
| Reviewer cannot mistake for production | Pass | Pass |
| All required states reachable | Pass | Pass |
| Empty / error states present | Pass (no-devices state) | Partial (idle state present; no "no hardware input" error state) |
| Reversibility / cancel path present | Pass (cancel arm present) | Pass |
| Progressive disclosure respected | Pass | Pass |
| Primary goal confirmed within stated budget | Pass (2 interactions) | Pass (3 interactions) |
| Open questions surfaced in prototype | Pass | Pass |

---

## Per-Prototype Assessment

### Prototype 01 — Audio Preferences: Interface Selection

**Primary goal:** select an audio interface in <= 2 interactions (click Audio
tab, pick device from list). The prototype already starts on the Audio tab, so
in practice the goal is 1 interaction from the open-preferences state.

**What works:**

- The four-state model (default, no-devices, applying, applied) is complete and
  all states are reachable via the state bar. The `no-devices` empty state is
  explicit and actionable ("Connect an audio interface and reopen Preferences").
- Independent input and output device lists match the most common real-world
  setup (Scarlett as interface, MacBook speakers as fallback output) without
  forcing an aggregate device.
- The `applying` → `applied` auto-transition (1.2 s simulated delay, inputs
  disabled, busy status dot) correctly communicates that the engine is being
  rewired. The confirmation banner names the newly selected device.
- The status row below each list (sample rate, buffer size, "active" green dot)
  gives enough context to confirm the device is live without burying the user in
  driver detail.
- MIDI tab consistency: the two-column MIDI-style layout is matched (label
  column left, control right). The Audio tab will feel at home next to the MIDI
  tab the user already knows.
- Secondary controls (sample rate, buffer size) are visually subordinated with
  a dashed section divider and reduced opacity. They are present for completeness
  but clearly secondary. Open Q3 (defer to a separate milestone?) is correctly
  noted in the prototype comment.
- Stub treatment is correct: General, MIDI, and Updates tabs are dashed and
  non-interactive.

**What is limited or missing:**

- There is no error state for a device that is listed but fails to initialise
  (e.g., driver error after selection). The `applying` state only transitions
  to `applied`; there is no `failed` state. This is a meaningful gap for a
  feature that touches CoreAudio — spec must define what the UI shows when the
  engine swap fails.
- When the output device is changed, there is no status update for the output
  row (only the input row has the `input-status-label` update). Minor omission
  for a prototype, but spec should confirm both sides update.
- The device list uses a scrollable panel capped at 140px. Fixture data has four
  devices, which fits. A real machine with eight or more devices (common in
  studio use: multiple interfaces, virtual devices, Bluetooth, etc.) would
  require scrolling. The prototype does not test this stress case. Note for spec.
- Open Q2 (independent vs. aggregate device selection) is called out in the
  prototype comments but not visualised. The prototype implicitly adopts
  independent selection. This is the right UX assumption but must be confirmed
  before spec.
- Q4 (missing device at next launch) has no visual representation. The no-devices
  state shows a completely empty list; a partial state (previously selected device
  missing, other devices still present) is not prototyped. Spec must cover this.

**User story coverage:**

| Story | Coverage |
|---|---|
| 1. Select an audio interface | Fully covered: pick input device, pick output device, apply transition, confirmation |

---

### Prototype 02 — Audio Input Track Workspace Page

**Primary goal:** arm → record → loop in <= 3 interactions (select bar length,
press ARM, recording auto-starts and auto-stops). The prototype demonstrates
this end-to-end with animated waveform fill and automatic state transitions.

**What works:**

- The six-state machine (idle, monitoring, armed, recording, loop, loop-input)
  covers the full lifecycle of the track. All states are reachable from the
  state bar and via the ARM button interaction.
- The ARM button is the clearest interaction in the prototype. It pulses amber
  when armed ("ARMED — tap to cancel"), shows a countdown indicator, then
  transitions to a solid red "RECORDING" state. The pending-trigger concept from
  Story 5 (Octatrack-style quantized arm) is well communicated. The cancel path
  (tap ARM while armed to cancel) is discoverable and implemented.
- The bar-length segmented control (1 / 2 / 4 / 8 bars) is correctly locked
  during armed and recording states so the user cannot change length mid-capture.
  Bar length defaults to 2 bars, which is a reasonable default.
- The Input/Loop mode toggle (Story 6) is immediately visible above the waveform
  area. The hint text ("Monitoring live hardware input" / "Playing recorded loop")
  removes ambiguity about what signal is reaching the output.
- The waveform panel correctly shows level meters in input mode and a waveform
  in loop mode. The real-time fill animation during recording gives the user
  progress feedback and shows how far through the bar length the recording has
  progressed. Switching to `loop-input` state (Loop buffered, input monitoring
  active) is a meaningful third mode that the user stories implied but did not
  name explicitly; the prototype surfaces it correctly.
- The track header HW Input selector (Ch 1, Ch 2, Stereo) anticipates a
  per-track channel assignment that the user stories do not explicitly call out
  but which is practically necessary. This is a useful addition to surface for
  spec.
- The mixer routing stub at the bottom is correctly dashed and labelled. It
  grounds the track in the mixer architecture without building it.
- The annotation block below the prototype restates the click-path and surfaces
  all five open questions (step-pattern grid, live signal in loop mode, overdub
  vs. replace, real-time waveform, BPM change after recording). These are
  genuine spec-level decisions.
- Dark app-shell chrome correctly matches a sequencer aesthetic and is visually
  distinct from the lighter Preferences prototype, grounding the two screens in
  different contexts.

**What is limited or missing:**

- The `loop-input` state (loop buffered, monitoring live input) does not show the
  waveform of the buffered loop alongside the level meters. A user in this state
  cannot see what loop is sitting in the buffer. Minor but worth noting: the spec
  should decide whether a thumbnail of the buffered waveform is visible in this
  state or whether it is only visible when the mode is fully switched to Loop.
- There is no "no hardware input connected" error state. If the selected audio
  interface has no input available (e.g., output-only device selected, or the
  interface was disconnected), the track page should communicate this. The
  prototype assumes a signal is always available once a track is created.
- Re-arming from the `loop` state is implemented (ARM button is active in loop
  state), but the prototype does not clearly communicate that pressing ARM while
  a loop is playing will destroy the existing loop once recording completes. Open
  Q3 (destructive replace vs. overdub) is called out, but the UI gives no warning
  at arm time. Spec must decide whether a confirmation or visual warning is needed
  before the old loop is overwritten.
- The prototype does not show what happens when the user navigates away from the
  track page (e.g., clicks another track in the sidebar) while recording is in
  progress. Does recording continue in the background? Does the ARM/recording
  state remain visible elsewhere? This is a missing flow.
- The HW Input selector on the track header is not connected to the waveform or
  level meters — selecting a different channel has no effect in the prototype.
  This is acceptable for a prototype but is a real interaction that spec must
  cover (channel change while recording active, channel change while loop is
  playing).
- The step-pattern question (Open Q1) is unresolved. Slicer has a step grid; the
  input audio notes do not mention one. This is a meaningful product decision:
  if the track gets a step pattern, the workspace layout needs a third region and
  the prototype does not account for the space.

---

## Head-to-Head: Are Two Separate Prototypes the Right Split?

The split (preferences in 01, track page in 02) is appropriate. The preferences
screen is a global app setting with its own interaction model; the track page is
a per-session object with a live state machine. They do not share layout regions
or interaction patterns. Evaluating them separately is correct.

No cross-prototype variant comparison is needed: neither screen has a competing
variant to choose between. Each prototype is the only candidate for its surface.

---

## Open Questions Surfaced (must resolve before or during spec)

The following questions appeared in the prototype comments and/or emerge from
this review. They are inputs for `open-questions.md` and must be resolved before
`spec.md` is written.

1. **Engine restart on device switch.** Does switching the audio interface
   require restarting the `AVAudioEngine`? The existing-state report says
   CoreAudio property-set can rewire without a full restart on macOS, but this
   needs validation. The preferences prototype assumes a short (~1 s) disabled
   state is sufficient; if a full restart is required the UX must indicate longer
   downtime.

2. **Independent vs. aggregate device selection.** Should input and output
   devices be independently selectable, or must they be the same aggregate device?
   The prototype shows independent selection. Confirm before spec.

3. **Sample rate / buffer size deferral.** Should sample rate and buffer size
   controls ship with device selection in this milestone, or are they deferred?
   The prototype includes them in a visually subordinated section. User stories
   only mention device selection.

4. **Missing device at next launch.** When the previously selected device is no
   longer connected at app launch, should the app fall back silently (use system
   default) or show an explicit warning? The `no-devices` state covers a fully
   empty device list; the partial-absence case is not prototyped.

5. **Engine device-switch failure state.** What does the preferences UI show when
   the CoreAudio rewire attempt fails? No failed/error state exists in the
   prototype.

6. **Step-pattern grid on audio input track.** Does the input audio track have a
   step-sequencer pattern grid (like slicer), or is the workspace purely the
   record/monitor view? This determines whether a third layout region is needed.

7. **Live input signal routing in loop mode.** When the user switches to Loop
   mode, does the live hardware input signal remain connected to the mixer (always
   pass-through) or is it gated (only in Input mode)? The mode hint text says
   "Playing recorded loop" in Loop mode, implying the input is no longer
   monitored, but the spec must be explicit about what reaches the mixer.

8. **Overdub vs. destructive replace.** When the user arms while a loop is
   already buffered, does recording overwrite the existing loop or is overdub
   supported? The prototype shows destructive replace with no warning. A
   confirmation or visual warning may be needed.

9. **Real-time waveform during recording.** Should the waveform fill in real time
   during recording (streamed) or render only after the recording stops? Real-time
   is richer UX; post-render is simpler to implement.

10. **BPM change after recording.** If the session BPM changes after a loop is
    recorded, the loop's sample length is fixed. Does the app pitch-shift, time-
    stretch, or leave the loop at its original duration (creating tempo drift)?
    Out of scope for this pass, but spec must explicitly exclude it.

11. **Per-track hardware channel selector.** The track header in prototype 02
    includes a hardware channel picker (Ch 1, Ch 2, Stereo). User stories do not
    explicitly call this out. Confirm whether multi-channel input track assignment
    is in scope for this milestone.

12. **Navigation away while recording.** If the user switches to another track's
    workspace while recording is in progress, does recording continue? How is the
    in-progress record state communicated from the track list / header?

---

## Recommendation

**Accept both prototypes and advance to `write-architecture`.**

The two prototypes together cover all seven user stories at an appropriate
fidelity level. The primary interaction paths (device selection, arm→record→loop)
are implemented and verifiable. The state machines are coherent and reversible.
The stub treatment is correct. Open questions are explicit rather than silently
resolved.

No rework is required. The open questions enumerated above are architecture-and-
spec concerns, not prototype-level failures. They should be written into
`open-questions.md` and resolved during the architecture and spec stages.

**Key inputs for the architecture stage:**

- The preferences prototype confirms that independent input/output device
  selection is the right UX shape. Architecture must define the CoreAudio device-
  switch API path and its failure modes.
- The track page prototype confirms that the six-state lifecycle (idle,
  monitoring, armed, recording, loop, loop-input) is the right model. Architecture
  must define how these states map to engine and document model fields.
- The pending-arm / quantized-trigger concept (ARM → countdown → auto-start at
  bar boundary) must be mapped onto the `TickClock` in `EngineController`. The
  existing-state report confirms the bar-boundary detection point exists but no
  arm-command kind does.
- The HW input channel selector per track (prototype Q on story 2) must be
  decided before the track model is specified — it affects whether `TrackType`
  or `Destination` carries the channel assignment.
- The step-pattern question (Q6 above) is a layout-level decision that must be
  made before the architecture document can specify the workspace view structure.

---

## Next Action

Advance to `write-architecture`. The twelve open questions above should be
written into `open-questions.md` for the architecture stage; questions 1, 2, 6,
7, and 8 in particular may require user input before spec can be written.
