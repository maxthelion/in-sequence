# Bug: realtime-path-lint does not enforce the routing guardrail

Found: adversarial review 2026-06-25.

realtime-path-lint.sh special-cases MainAudioGraph.swift to base_forbidden_regex
(lines ~55-60), DROPPING the graph_mutation_regex for the one file where all
routing mutations live. And graph_mutation_regex (line ~41) does not include
`engine.stop`/`engine.start`. So Rule 5 ("never engine stop/start during
playback; never disconnect a sounding node") has NO deterministic enforcement —
a regression here is invisible. The guardrail page claims it's lint-enforced; it
is not. (Tasks #39/#40/#41 — extended lint, offline frame test, adherence
observers — are also still unbuilt.)

Fix: enforce engine.stop/start + disconnect-of-sounding-node + lifecycleLock-
across-engine-mutation in routing paths. Task #50.

Status: RESOLVED — realtime-path-lint routing coverage (#50)
