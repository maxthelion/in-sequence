---
status: open
created: 2026-06-04T16:06:00Z
source: product-owner-review
applies_to: post-merge-step-sequencer
related_runtime_report: ~/Library/Logs/DiagnosticReports/SequencerAI-2026-06-04-164912.ips
---

# Track Source Step Grid Fill And Play Crash Feedback

The post-merge Track Source step-grid rework is directionally better: the
inspect/modal-first interaction has been removed and the cells are more compact.

Remaining issues:

- The step cells still do not fill the available editor well. The grid reads as
  a small shrunken component sitting in a large empty green panel rather than a
  purposeful full-width editing surface.
- The layout should use the horizontal space more intentionally while keeping
  step cells compact and readable.
- Pressing Play after this build produced a beachball/hang followed by a crash.
  The crash report points at `SamplePlaybackEngine.scheduleAndStart` /
  `AVAudioPlayerNode.play` with `player started when in a disconnected state`.

Runtime attribution note:

- The crash came from a pre-attribution-stamp build whose crash-visible
  `CFBundleVersion` was still `1`.
- The build pipeline has since been updated so future debug builds stamp
  `CFBundleVersion` with a build-attribution version and write a manifest under
  `.meta/multipass/build-attribution/`.

Suggested next work:

- Treat the grid-fill issue as a Step Sequencer / Track Source polish follow-up.
- Treat the play crash as runtime-regression evidence unless a current
  attributed rebuild shows it belongs to a specific active feature.
