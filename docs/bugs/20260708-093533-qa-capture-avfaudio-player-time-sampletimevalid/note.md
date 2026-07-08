QA capture abort: AVFAudio playerTime.sampleTimeValid during drum-kit rows

Status: OPEN

Observed: 2026-07-08 09:33 Europe/London during `scripts/visual-scenarios/qa-surface-coverage.sh` on dirty `main` at `923a889d`.

Capture run:
- Gallery: http://localhost:4747/gallery?run=20260708-083510-in-sequence-qa-surface-coverage-main-923a889d
- Source: `qa-surface-coverage`
- Absorbed images: 64
- Chord-track rows `23h`, `23i`, and `23j` completed before this crash.

Crash signature:
- Process: `SequencerAI[41557]`
- Exception: `com.apple.coreaudio.avfaudio`
- Reason: `required condition is false: playerTime && playerTime.sampleTimeValid`
- Top AVFAudio frame: `AVAudioPlayerNodeImpl::BufferCommand::Perform`

Scenario context:
- The last successful image was `29-drum-kit-matrix.png`.
- The app stopped advancing visual status while driving drum-kit rows:
  - `29a-drum-kit-fx-tab`
  - `29b-drum-kit-macros-tab`
  - `29c-drum-kit-mixer-tab`
  - `29d-drum-kit-expanded-generator`
  - `29f-drum-kit-capture-save-slot`
- Scenario log recorded status timeouts after the abort.

Is it new?
- Probably not new to the chord-track work. `.meta/multipass/state/runtime-problems.md` already records a 2026-07-06 `playerTime.sampleTimeValid` AVFAudio abort during sample playback / routing-stress status polling.
- This 2026-07-08 repro is new current evidence on dirty `main`, and it blocks a clean full QA capture, but it happened after the chord-track screenshots completed and in the later drum-kit/audio section of the capture table.

Expected:
- Visual QA capture should not crash the app or leave the command channel stale.
- Sample/drum-kit playback scheduling must avoid `AVAudioPlayerNode` commands when node time is invalid; fixes must respect the audio hard rules, especially schedule-ahead timing and fixed-graph routing.

Status: RESOLVED in this commit; fresh qa-surface-coverage run 20260708-090903-in-sequence-qa-surface-coverage-main-923a889d absorbed all 79 PNG rows without reproducing the AVFAudio abort. Rows 29c, 29d, and 29f needed narrow status-timeout backfills after the full run, so the crash is fixed but drum-kit command ack latency remains separate process evidence if it recurs.
