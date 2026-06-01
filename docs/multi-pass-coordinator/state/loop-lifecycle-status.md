# Loop Lifecycle Status

- generated: 2026-06-01T17:35:18.736Z
- project: `/Users/maxwilliams/dev/in-sequence`
- loops: 5

This is factual lifecycle evidence. It does not decide product completion.
The ticker should ignore terminal loops; observers/orienters/deciders use this
to notice stale active loops, merge candidates, and terminal-loop residue.

| loop | kind | status | branch | contained in main | worktree | pending | claimed | blocked | lifecycle signal |
| --- | --- | --- | --- | --- | --- | ---: | ---: | ---: | --- |
| `build/clip-history` | build | active | `auto/roadmap-1-clip-history-v2` | diverged | clean | 3 | 0 | 3 | active-loop-has-blocked-work |
| `build/mixer-busses` | build | complete | `auto/roadmap-5-mixer-busses-ui-finish` | yes | clean | 0 | 0 | 8 | none |
| `build/scene-perform` | build | complete | `auto/roadmap-2-scene-perform` | yes | dirty | 1 | 0 | 1 | terminal-loop-has-open-messages |
| `build/step-sequencer` | build | active | `auto/roadmap-3-step-sequencer` | diverged | clean | 2 | 0 | 7 | active-loop-has-blocked-work |
| `project` | project | active |  | n/a | n/a | 3 | 1 | 19 | active-loop-has-blocked-work |

