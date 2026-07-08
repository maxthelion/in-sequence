QA drum-kit command ack latency during surface capture

Status: OPEN

Observed during review of `16ac1dea` against
`docs/plans/2026-07-08-today-ux-bug-batch-goal.md`.

Capture run:
- Gallery: http://localhost:4747/gallery?run=20260708-090903-in-sequence-qa-surface-coverage-main-923a889d
- Source: `qa-surface-coverage`

What happened:
- The fresh full capture did not reproduce the AVFAudio
  `playerTime.sampleTimeValid` abort.
- The full run still produced only 76/79 rows because drum-kit command status
  acknowledgements timed out for:
  - `29c-drum-kit-mixer-tab`
  - `29d-drum-kit-expanded-generator`
  - `29f-drum-kit-capture-save-slot`
- Those rows were rerun narrowly and backfilled into the capture inbox before
  absorb, so the gallery has all 79 PNGs, but the evidence was not a single
  uninterrupted full pass.

Expected:
- `scripts/visual-scenarios/qa-surface-coverage.sh` should complete all
  drum-kit rows in one full run without status-ack timeouts or row backfills.
- If drum-kit rows legitimately need a longer render/ack window, the script
  should encode that deterministically rather than relying on manual reruns.
