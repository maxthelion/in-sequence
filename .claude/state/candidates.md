# Reconnaissance Findings — 2026-04-19

Produced by a read-only probe run from a worktree at HEAD `4f47ef9`. Written to preserve context before `/loop /execute-plan` for `characterization`.

## Headline: Plan 1 needs an amendment before overnight execution

**`Sources/` contains ZERO `public` or `open` declarations.** This is a single-target Xcode app where every type is implicit-internal. Running `DumpAPI` as specified in Plan 1 (Tasks 1–2) against the codebase would produce **empty golden files** — there is nothing public to pin.

The characterization plan's "API surface" layer needs re-scoping to one of:

- **All type declarations** (159 types; covers the full surface)
- **Implicit-internal declarations only** (98 types; matches "API" intent)
- **Cross-file-referenced declarations** (the true interface — types another file reads/writes)
- **Declarations in files that are `import`ed from outside their directory** (module-equivalent in single-target land)

Option 3 is closest to Feathers-style "what would a refactor break if it changed the signature." But it requires a reference-graph walk, not just a syntax walk — bigger Task 1. Option 1 is mechanical and safe — arguably the right MVP.

**Recommendation:** amend Plan 1 Task 1 to dump all type declarations (not just `public`) before executing overnight. Otherwise the plan completes and produces a safety net with holes.

## Codebase shape

| Module | LOC | Notes |
|---|---|---|
| UI | 8270 | 42% of codebase. Covered by SwiftUI snapshots (qa-infrastructure plan, separate). |
| Document | 5574 | Includes `SeqAIDocumentModel.swift` (1249 LOC) and `PhraseModel.swift` (905 LOC). |
| Engine | 2908 | `EngineController.swift` at 776 LOC. |
| Audio | 1346 | AVFoundation / AU hosting. |
| MIDI | 764 | |
| Platform | 360 | |
| Musical | 354 | Scale / chord / algo logic. |
| App | 68 | SwiftUI shell. |
| Resources | — | No Swift. |

**Total: ~19,600 LOC, 159 type declarations across 9 directories.**

## Files exceeding the 1000-LOC cap

- `Sources/UI/PhraseWorkspaceView.swift` — **1409 LOC** (already over the cap — flag for split)

## Files over 500 LOC (watch-list)

- `Sources/Document/SeqAIDocumentModel.swift` — 1249
- `Sources/Document/PhraseModel.swift` — 905
- `Sources/UI/DetailView.swift` — 787
- `Sources/Engine/EngineController.swift` — 776

## Complexity hotspots (lizard, CCN > 15)

Only one warning in the whole codebase:
- `PitchAlgo.pick` — NLOC 70, CCN **20**, 606 tokens. Candidate for decomposition. Pin with algo goldens before touching.

Average CCN across the codebase is 2.8 — very healthy. This is not a tangled codebase.

## Test coverage signal

- 37 test files vs 159 type declarations = thin. Characterization goldens will materially improve this.
- Only 2 TODO/FIXME markers in `Sources/` — genuinely low technical-debt text markers.

## Tool availability

- `lizard` — installed at `~/.local/bin/lizard`. Works on Swift.
- `jscpd` — NOT installed. Needed for duplication detection if we want the octoclean-style score.
- `octoclean` — installed at `/Users/maxwilliams/dev/octoclean/`. JS/TS-focused (`codehealth` binary). Would need adapting for Swift or used only via its LLM-assessment layer. Deferred to Plan 3 (overnight-bt-extension).
- `xcodebuild` — available via Xcode 16.
- `swift-syntax` — available as SPM dependency (used by Plan 1's DumpAPI tool).

## Implication for the overnight run

Given the findings:

1. **Don't run Plan 1 as-written tonight.** The DumpAPI task produces empty files. Either:
   - (a) amend the plan first (5-minute edit to specify scope = all type declarations, not just `public`), then run
   - (b) let the plan run and accept Task 1–2 produce empty-but-valid goldens; re-scope in a follow-up plan
2. **Other tasks are fine as-specified.** Document round-trips, engine tick traces, algo outputs, MIDI packets, route resolution — all pin actual observable behaviour regardless of access-control modifiers.
3. **Plans 2 + 3 now captured** as `2026-04-19-cleanup-post-reshape.md` and `2026-04-19-overnight-bt-extension.md` (both DRAFT).

## Notes on WIP

Probe was run from a worktree off HEAD. The main checkout has 5 modified files (Audio, Engine, UI + 2 test files) — work-in-progress, untouched by this investigation.
