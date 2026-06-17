# Loop Lifecycle Status

- generated: 2026-06-17T07:19:07.394Z
- project: `/Users/maxwilliams/dev/in-sequence`
- loops: 33

This is factual lifecycle evidence. It does not decide product completion.
The ticker should ignore terminal loops; observers/orienters/deciders use this
to notice stale active loops, merge candidates, and terminal-loop residue.

| loop | kind | status | branch | contained in main | worktree | pending | claimed | blocked | lifecycle signal |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `build/au-discovery-rescan` | build | active | `feature/au-discovery-rescan` | branch-ahead | clean | 0 | 0 | 3 | active-loop-has-blocked-work |
| `build/autoslice-algorithm` | build | complete | `auto/roadmap-13-autoslice-algorithm` | yes | missing | 0 | 0 | 5 | none |
| `build/clip-history` | build | complete | `auto/roadmap-1-clip-history-v2` | yes | missing | 0 | 0 | 128 | none |
| `build/drum-parts-as-group` | build | complete | `auto/roadmap-12-drum-parts-as-group` | yes | missing | 0 | 0 | 14 | none |
| `build/input-audio` | build | complete | `auto/roadmap-7-input-audio` | yes | missing | 0 | 0 | 32 | none |
| `build/midi-interfaces` | build | locked | `auto/roadmap-8-midi-interfaces` | diverged | clean | 0 | 0 | 15 | active-loop-has-blocked-work |
| `build/mixer-busses` | build | complete | `auto/roadmap-5-mixer-busses-ui-finish` | yes | missing | 0 | 0 | 8 | none |
| `build/note-repeat` | build | complete | `auto/roadmap-15-note-repeat` | yes | missing | 0 | 0 | 12 | none |
| `build/observability-log-issues` | build | locked | `auto/roadmap-21-observability-log-issues` | diverged | dirty | 0 | 0 | 20 | active-loop-has-blocked-work |
| `build/performance-layer-matrix` | build | complete | `auto/roadmap-performance-layer-matrix` | yes | missing | 0 | 0 | 5 | none |
| `build/phrase-features` | build | complete | `auto/roadmap-10-phrase-features` | yes | missing | 0 | 0 | 13 | none |
| `build/routing-source-mixer-split` | build | active | `feature/routing-source-mixer-split` | diverged | clean | 0 | 0 | 5 | active-loop-has-blocked-work |
| `build/scene-perform` | build | complete | `auto/roadmap-2-scene-perform` | yes | dirty | 0 | 0 | 1 | none |
| `build/song-mode-phrase-looping` | build | complete | `auto/roadmap-11-song-mode-phrase-looping` | yes | missing | 0 | 0 | 4 | none |
| `build/step-order` | build | complete | `auto/roadmap-16-step-order` | yes | missing | 0 | 0 | 16 | none |
| `build/step-sequencer` | build | complete | `auto/roadmap-3-step-sequencer` | yes | missing | 0 | 0 | 274 | none |
| `build/track-fill-toggle` | build | complete | `auto/roadmap-18-track-fill-toggle` | yes | missing | 0 | 0 | 4 | none |
| `build/track-perform-multiselect-latch` | build | complete | `auto/roadmap-24-track-perform-multiselect-latch` | yes | missing | 0 | 0 | 4 | none |
| `pm/audio-looping` | pm | locked |  | n/a | n/a | 0 | 0 | 1 | active-loop-has-blocked-work |
| `pm/autoslice-algorithm` | pm | active |  | n/a | n/a | 0 | 0 | 0 | active-pm-feature-build-complete |
| `pm/drum-parts-as-group` | pm | complete |  | n/a | n/a | 0 | 0 | 0 | none |
| `pm/fill-clip-from-generator` | pm | complete |  | n/a | n/a | 0 | 0 | 0 | none |
| `pm/input-audio` | pm | complete |  | n/a | n/a | 0 | 0 | 2 | none |
| `pm/midi-interfaces` | pm | complete |  | n/a | n/a | 0 | 0 | 0 | none |
| `pm/note-repeat` | pm | active |  | n/a | n/a | 0 | 0 | 1 | active-pm-feature-build-complete |
| `pm/observability-log-issues` | pm | active |  | n/a | n/a | 0 | 0 | 0 | active-pm-feature-build-started |
| `pm/phrase-features` | pm | complete |  | n/a | n/a | 0 | 0 | 0 | none |
| `pm/scenes-in-phrases` | pm | locked |  | n/a | n/a | 0 | 0 | 0 | none |
| `pm/song-mode-phrase-looping` | pm | complete |  | n/a | n/a | 2 | 0 | 0 | terminal-loop-has-open-messages |
| `pm/step-order` | pm | active |  | n/a | n/a | 0 | 0 | 0 | active-pm-feature-build-complete |
| `pm/track-fill-toggle` | pm | complete |  | n/a | n/a | 2 | 0 | 0 | terminal-loop-has-open-messages |
| `pm/track-perform-multiselect-latch` | pm | complete |  | n/a | n/a | 0 | 0 | 0 | none |
| `project` | project | active |  | n/a | n/a | 0 | 2 | 120 | active-loop-has-blocked-work |
