Type the DrumKitMatrixView rendered-visual-state notification payload (AC5.2)

Deferred follow-up from the track-view-ia review goal (docs/roadmap/track-view-ia-followup/goal.md, W5/AC5.2).

Problem:
`DrumKitMatrixView.postRenderedVisualState` (Sources/UI/DrumGroup/DrumKitMatrixView.swift, ~line 407) posts a NotificationCenter `userInfo` as `[String: Any]` with ~28 heterogeneous entries, plus an `expandedPartIndex == -1` sentinel for "no expanded part". This hits two code-review-checklist red flags: a `[String: Any]` payload (§10) and a magic-number sentinel in place of an optional (§1).

Why it was deferred (not just fixed):
The payload is consumed by an EXTERNAL QA path — `VisualScenarioCommandRunner` reads the string keys (e.g. userInfo["visible"], ["layer"], ["expandedPartIndex"]) and the scripts/visual-scenarios/*.sh asserts depend on the resulting status values. Fully typing the payload would break the observability/QA-capture protocol. The W5 agent correctly left the keys byte-for-byte intact.

Safe approach for the fix:
- Introduce a typed `DrumKitRenderedVisualState` struct (using `Int?` for the expanded part, etc.).
- Build it in the view, then SERIALIZE it into the SAME string-keyed userInfo at the notification boundary (keeping `expandedPartIndex == -1` only as the wire encoding of `nil`), so VisualScenarioCommandRunner + the shell asserts keep working unchanged.
- The struct gives the in-process producer a typed contract; the boundary keeps QA compatibility.

Acceptance:
- A typed `DrumKitRenderedVisualState` is the producer-side type.
- The posted userInfo keys/values are unchanged (verify against VisualScenarioCommandRunner + scripts/visual-scenarios/drum-kit-matrix.sh).
- No `-1` sentinel in the Swift type (only at the wire boundary).
- Build green; the drum-kit visual-scenario capture still passes.
