# Characterization Testing Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make overnight refactoring safe by pinning current observable behaviour into a battery of golden-file tests (Michael-Feathers-style characterization tests). Before any refactor commit, `scripts/verify-characterization.sh` re-runs the battery and compares against golden outputs; any diff fails the build and the refactor is reverted automatically. Goldens are only updated via explicit `chore(golden):` commits — overnight agents are forbidden from touching them. The pinned layers: public API signatures (swift-syntax AST dump), document Codable round-trips + legacy migration pairs, engine tick traces for scenario fixtures, algo outputs under seeded RNG, MIDI packet byte-streams, and route-resolution dispatches. Verified by: running `bash scripts/characterize.sh` captures ≥30 golden files under `Tests/__Characterization__/`; running `bash scripts/verify-characterization.sh` passes against the current HEAD; a deliberate breaking change (e.g. renaming a public method) causes verify to fail with a diff.

**Architecture:** Characterization outputs land in `Tests/__Characterization__/` (committed, diff-able). The pin-capture logic is per-layer:

1. **API surface:** A Swift executable `scripts/DumpAPI/` built as a standalone SPM package. Walks `Sources/**/*.swift` via `swift-syntax`, emits a canonical text dump of every non-`private`/`fileprivate` declaration per directory. Because this is a single-target Xcode app with no explicit `public` modifier usage, the pinned surface is implicit-internal + explicit `internal` + any future `public`/`open` — i.e. every declaration a refactor could observably change for another file. Output files: `Tests/__Characterization__/API/<Module>.api.txt`.
2. **Document + migration goldens:** Fixture JSON files covering one "minimal doc" + one "legacy drumRack doc" + one "legacy instrument" + one full-featured modern doc. Each has a `.input.json` (the document as shipped) and `.decoded.txt` (a canonical rendering of the decoded model). `characterize` writes `.decoded.txt`; `verify` decodes `.input.json` and compares.
3. **Engine tick traces:** Scenario fixtures construct an `EngineController` with fixed seed + fixed document, tick for N beats, record the MIDI event sequence as a text log (`Tests/__Characterization__/Engine/<scenario>.log`).
4. **Algo outputs:** Pairs of `<Algo>.<variant>.seed-<N>.txt` goldens — input params + RNG seed → enumerated output (which steps fire, which pitches picked). Many of these already exist as assertions inside unit tests; this task systematises them as golden files.
5. **MIDI packets:** Hex dumps of packet lists produced by `MIDIPacketBuilder` for canonical note sequences.
6. **Route resolution:** A tabular golden per fixture: `(sourceTrack, noteEvent, routes) → dispatched destinations`.

The CI entry point: a single `scripts/verify-characterization.sh` script that runs all 6 layers and exits nonzero on any diff.

**Tech Stack:** Swift 5.9+, swift-syntax (SPM package dependency for the `DumpAPI` tool), XCTest, Foundation, bash. No runtime dependencies on the sequencer app (tools live in `scripts/`).

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`. This is QA infrastructure — not a subsystem per se — but underpins the overnight-refactoring capability the BT is evolving toward.

**Environment note:** Xcode 16 at `/Applications/Xcode.app`. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. The `DumpAPI` SPM package builds on Linux too (swift-syntax is cross-platform), so the API characterization layer works even in xcodebuild-less sandboxes.

**Status:** <STATUS_PREFIX> <COMPLETED_MARKER> TBD. Tag `v0.0.11-characterization` at TBD.

**Depends on:** nothing hard. Can execute before or after the track-group reshape — but characterization captured BEFORE the reshape pins the current (pre-reshape) behaviour; the reshape's refactors then migrate the goldens explicitly. Recommended order: ship this plan first, THEN reshape.

**Deliberately deferred:**

- **View snapshot tests.** Already in the `qa-infrastructure` plan (Task 2-3). Not duplicated here.
- **Audio output characterization.** Requires an offline render path; skipped for MVP (the tick-trace layer pins event sequences, which is upstream of audio).
- **Performance benchmarks.** Not characterization; belongs in a perf plan.
- **Characterization for the UI layer beyond API dumps.** SwiftUI snapshots cover rendering; state-transition characterization is a follow-up.
- **LLM-driven characterization diffs.** When a golden fails, MVP prints the raw diff. A future wrapper could ask an LLM to summarise *what the behavioural change looks like* in English. Deferred.

---

## File Structure

```
scripts/
  DumpAPI/                                 # NEW — standalone SPM package
    Package.swift
    Sources/DumpAPI/main.swift             # swift-syntax AST walker
  characterize.sh                          # NEW — one-shot capture of all goldens
  verify-characterization.sh               # NEW — run against current code; diff goldens
  dump-api.sh                              # NEW — wrapper for the SPM tool
Tests/
  SequencerAITests/
    Characterization/                      # NEW — test-side assertions that load goldens
      APISurfaceTests.swift
      DocumentRoundTripTests.swift
      EngineTickTraceTests.swift
      AlgoGoldenTests.swift
      MIDIPacketGoldenTests.swift
      RouteResolutionGoldenTests.swift
      CharacterizationFixtures.swift       # shared scenario builders
  __Characterization__/                    # NEW — committed golden files
    API/
      Document.api.txt
      Engine.api.txt
      MIDI.api.txt
      Musical.api.txt
      Audio.api.txt
    Documents/
      minimal.input.json
      minimal.decoded.txt
      legacy-drumrack.input.json
      legacy-drumrack.decoded.txt
      full.input.json
      full.decoded.txt
    Engine/
      mono-kick-16bars.log
      four-track-polymeter.log
    Algos/
      stepalgo-manual-seed-42.txt
      stepalgo-euclidean-3-8-0.txt
      pitchalgo-randomInScale-seed-42.txt
      pitchalgo-markov-seed-42.txt
    MIDI/
      note-on-off-pair.hex
      three-note-chord.hex
    Routes/
      single-route.txt
      fan-out.txt
.github/
  workflows/
    ci.yml                                 # NEW — runs verify-characterization on every push
```

---

## Task 1: `DumpAPI` SPM tool

**Scope:** Standalone Swift command-line tool that reads `Sources/**/*.swift` and emits canonical text dumps of every non-`private`/`fileprivate` top-level declaration per module. Uses swift-syntax. Cross-platform.

**Access-control note:** This is a single-target Xcode app; `Sources/` contains zero `public`/`open` declarations and 98 implicit-internal type declarations across 9 directories. "API surface" here therefore means **every declaration that another file could reference** — i.e. everything NOT marked `private` or `fileprivate`. `public`/`open` is treated as a synonym for "definitely in scope," but implicit-internal and explicit `internal` declarations ARE included. This matches the Feathers intent: pin whatever a refactor could observably change.

**Files:**
- Create: `scripts/DumpAPI/Package.swift`
- Create: `scripts/DumpAPI/Sources/DumpAPI/main.swift`
- Create: `scripts/dump-api.sh` (wrapper that invokes `swift run --package-path scripts/DumpAPI DumpAPI ...`)
- Create: `Tests/SequencerAITests/Characterization/APISurfaceTests.swift`

**Tool behaviour:**

```
dump-api <module-directory> > <module>.api.txt
```

Walks the directory, parses each `.swift` file via `SwiftSyntaxParser`, visits every top-level declaration (struct, class, enum, actor, typealias, protocol, extension, function, variable) AND their members, emitting a one-line canonical signature per declaration. **Skip** any declaration explicitly marked `private` or `fileprivate`. Include everything else (no modifier = implicit-internal = in scope; `internal` = in scope; `public`/`open` = in scope). Enum cases with associated values get their own line. Extensions emit as `extension TypeName: Protocol, ...` plus one line per non-private member. Output sorted deterministically (lexicographic by fully-qualified name, then by signature).

Each declaration line is prefixed with its effective access level (`internal` for implicit-internal) so that future promotions from internal → public show up as diffs.

Example output snippet (adapted to the actual codebase):

```
internal typealias TrackID = UUID
internal struct Track: Codable, Equatable, Identifiable
internal struct Track { let id: TrackID }
internal struct Track { var name: String }
internal struct Track { var destination: Destination }
internal enum TrackType: String, Codable { case instrument }
internal enum TrackType: String, Codable { case drumRack }
internal enum TrackType: String, Codable { case group }
internal extension Track: Hashable
internal func Track.hash(into: inout Hasher)
...
```

**Tests:**

1. Running against a fixture directory with one implicit-internal struct + one explicit-private struct produces output containing only the internal one.
2. `private` and `fileprivate` declarations are omitted; `public`, `open`, `internal`, and no-modifier declarations are all included.
3. Output is deterministic across multiple runs.
4. Adding a new non-private method to any type changes the dump.
5. Changing a declaration's access level from `internal` to `public` shows up as a diff (the `internal` prefix changes to `public`).

- [ ] Write `APISurfaceTests` with fixture-based assertions
- [ ] Implement the tool
- [ ] Wrapper script
- [ ] Green
- [ ] Commit: `feat(scripts): DumpAPI swift-syntax tool`

---

## Task 2: API surface goldens

**Scope:** Generate the initial `Tests/__Characterization__/API/<Module>.api.txt` files for every directory under `Sources/` (treated as a module for characterization purposes). These become the baselines. Expected baseline size: ~98 type declarations + their members across 9 directories → on the order of several hundred lines total. Empty output for a directory is a bug (means the tool missed implicit-internal decls).

**Files:**
- Create: `Tests/__Characterization__/API/Document.api.txt` (etc. — one per module)
- Modify: `Tests/SequencerAITests/Characterization/APISurfaceTests.swift` — load each golden, assert current output matches

**Tests:**

- One `test_<module>_api_surface_matches_golden` per module: runs `dump-api Sources/<Module>`, compares against `__Characterization__/API/<Module>.api.txt`, fails with diff on mismatch.

- [ ] Run `bash scripts/dump-api.sh` for each module, commit the outputs
- [ ] Extend `APISurfaceTests.swift` with per-module tests
- [ ] Green
- [ ] Commit: `test(characterization): API surface goldens for all modules`

---

## Task 3: Document + migration goldens

**Scope:** Fixture JSON files covering representative document shapes; a golden `.decoded.txt` for each shows what the model contains after decoding.

**Files:**
- Create: `Tests/__Characterization__/Documents/minimal.input.json` — a freshly-created empty project
- Create: `Tests/__Characterization__/Documents/minimal.decoded.txt` — canonical rendering of the decoded model
- Create: `Tests/__Characterization__/Documents/legacy-drumrack.input.json` — a project with the old `.drumRack` track type + per-tag Voicing
- Create: `Tests/__Characterization__/Documents/legacy-drumrack.decoded.txt`
- Create: `Tests/__Characterization__/Documents/legacy-instrument.input.json` + `.decoded.txt`
- Create: `Tests/__Characterization__/Documents/full.input.json` + `.decoded.txt` — exercises every field
- Create: `Tests/SequencerAITests/Characterization/DocumentRoundTripTests.swift`

**Canonical rendering:** a deterministic dump of the decoded `SeqAIDocumentModel` — track names + types + destinations + pattern banks + generator pool + phrases + routes, formatted as indented text, sorted by ID where order isn't semantic. Helper `CanonicalRenderer.render(_:) -> String` in `CharacterizationFixtures.swift`.

**Tests (one per fixture):**

1. `test_minimal_document_decodes_as_expected`: load `minimal.input.json`, decode to `SeqAIDocumentModel`, render canonically, compare against `minimal.decoded.txt`.
2. Similar for each fixture.
3. `test_legacy_drumrack_migrates_to_flat_tracks_and_group` is a SEPARATE test that additionally asserts the shape conforms to the post-reshape model (will fail until reshape plan executes — correct: characterization is pinning current behaviour, which we will change deliberately).

- [ ] Author fixtures (hand-edit JSON)
- [ ] CanonicalRenderer helper
- [ ] DocumentRoundTripTests
- [ ] Capture goldens by running characterize.sh
- [ ] Green against current code
- [ ] Commit: `test(characterization): document + migration goldens`

---

## Task 4: Engine tick-trace goldens

**Scope:** Deterministic scenarios that tick the engine for a known number of beats and record every MIDI event emitted. Golden file is a text log of `(tick, trackID, eventKind, pitch, velocity, length)` tuples.

**Files:**
- Create: `Tests/__Characterization__/Engine/mono-kick-16bars.log` — a single mono track with a 4-on-the-floor manual step pattern, 16 bars, kick note
- Create: `Tests/__Characterization__/Engine/four-track-polymeter.log` — a 3-against-4 polymeter fixture
- Create: `Tests/__Characterization__/Engine/muted-track.log` — verify mute drops events
- Create: `Tests/__Characterization__/Engine/route-fan-out.log` — verify routes produce correct dispatch sequence
- Create: `Tests/SequencerAITests/Characterization/EngineTickTraceTests.swift`

**Fixture builder:**

```swift
func buildDocument(scenario: String) -> SeqAIDocumentModel { ... }
func runEngineFor(_ ticks: Int, seed: UInt64) -> [MIDIEventTrace] { ... }
```

RNG is explicitly seeded (for generators using `.randomWeighted` etc.). Time is injected (no real-clock dependency).

**Tests (one per scenario):**

- Load fixture, tick, compare event trace against golden.

- [ ] Author fixtures
- [ ] Capture goldens
- [ ] EngineTickTraceTests (4 scenarios)
- [ ] Green
- [ ] Commit: `test(characterization): engine tick-trace goldens`

---

## Task 5: Algo, MIDI packet, route-resolution goldens

**Scope:** Three smaller golden groups, done in one task.

**Files:**

*Algo goldens* (extend existing algo tests by dumping outputs to files):
- Create: `Tests/__Characterization__/Algos/stepalgo-manual-seed-42.txt` (and ~10 similar)
- Create: `Tests/__Characterization__/Algos/pitchalgo-*.txt` (~10 similar)
- Modify: `Tests/SequencerAITests/Characterization/AlgoGoldenTests.swift` — parameterised test loads each golden and compares output

*MIDI packet goldens:*
- Create: `Tests/__Characterization__/MIDI/note-on-off-pair.hex` — hex dump of the packet list
- Create: `Tests/__Characterization__/MIDI/three-note-chord.hex`
- Create: `Tests/__Characterization__/MIDI/cc-envelope-sweep.hex`
- Create: `Tests/SequencerAITests/Characterization/MIDIPacketGoldenTests.swift`

*Route resolution goldens:*
- Create: `Tests/__Characterization__/Routes/single-route.txt` — tabular: `(sourceTrack, note) → dispatches`
- Create: `Tests/__Characterization__/Routes/fan-out.txt`
- Create: `Tests/__Characterization__/Routes/chord-context.txt`
- Create: `Tests/SequencerAITests/Characterization/RouteResolutionGoldenTests.swift`

- [ ] Author fixtures + capture goldens for all three layers
- [ ] Test classes for each
- [ ] Green
- [ ] Commit: `test(characterization): algo + MIDI packet + route-resolution goldens`

---

## Task 6: `characterize.sh` + `verify-characterization.sh`

**Scope:** Two shell scripts tying it all together.

**Files:**
- Create: `scripts/characterize.sh` — regenerates ALL goldens; meant to be run manually after deliberate behaviour changes
- Create: `scripts/verify-characterization.sh` — runs the test suite with a `--only-characterization` filter; exits nonzero on any diff

**`characterize.sh` sequence:**

1. Echo "This regenerates all golden files. Only run after deliberate behaviour changes."
2. Prompt for confirmation (with `--yes` to skip)
3. Run `bash scripts/dump-api.sh Sources/<Module> > Tests/__Characterization__/API/<Module>.api.txt` for each module
4. Run the xcodebuild test target with a `-resetGoldens=1` env var that the test classes respect: on set, they write goldens instead of comparing
5. Summarise: N goldens written, git diff summary

**`verify-characterization.sh` sequence:**

1. `bash scripts/dump-api.sh` into a tempdir, diff against `Tests/__Characterization__/API/`; nonzero on diff
2. `DEVELOPER_DIR=... xcodebuild test -only-testing:SequencerAITests/Characterization/*` — runs the test classes in compare mode
3. Exit status reflects failures

**Tests:** manual verification — a deliberate breaking change (rename any non-private method, e.g. on `Track` or `EngineController`) fails verify; running `characterize --yes` then verify passes.

- [ ] Write both scripts
- [ ] Wire `-resetGoldens=1` handling into the test classes
- [ ] Manual smoke
- [ ] Commit: `build(scripts): characterize.sh + verify-characterization.sh`

---

## Task 7: GitHub Actions CI running `verify-characterization`

**Scope:** On every push to `main` + every PR, run the full characterization suite on a macOS runner. Green = HEAD preserves pinned behaviour.

**Files:**
- Create: `.github/workflows/ci.yml`

**Workflow:**

```yaml
name: CI
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: "0 2 * * *"        # nightly sanity check

jobs:
  characterization:
    runs-on: macos-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0        # full history for churn metrics
      - name: Install xcodegen
        run: brew install xcodegen
      - name: Generate xcodeproj
        run: xcodegen generate
      - name: Run characterization suite
        env:
          DEVELOPER_DIR: /Applications/Xcode.app/Contents/Developer
        run: bash scripts/verify-characterization.sh
      - name: Upload diff on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: characterization-diff
          path: /tmp/characterization-diff
```

**Tests:** push a test PR; verify the workflow runs and reports green.

- [ ] Workflow file
- [ ] Test with a PR
- [ ] Commit: `build(ci): GitHub Actions verify-characterization on every push`

---

## Task 8: Pre-commit hook — no duplicate top-level types

**Scope:** Adversarial review's recurring-pattern insight: the TrackGroup duplicate build-breaker should never recur. Pre-commit hook greps `Sources/**/*.swift` for duplicate `^(public\s+)?(struct|class|enum|actor|typealias|protocol)\s+\w+` declarations; commits refuse if any top-level type name appears in more than one file.

**Files:**
- Create: `.claude/hooks/pre-commit-no-duplicate-types.sh`
- Modify: `.claude/settings.json` — wire the hook into the PreToolUse Bash handler for `git commit` commands

**Hook logic:**

```bash
#!/usr/bin/env bash
# Pre-commit: refuse if any top-level Swift type name is declared in more than one file.
cd "$(git rev-parse --show-toplevel)"
dupes=$(grep -HnE '^(public\s+)?(struct|class|enum|actor|typealias|protocol)\s+\w+' Sources/**/*.swift \
  | awk -F: '{
      line=$0; sub(/^[^:]+:[0-9]+:/, "", line);
      match(line, /(struct|class|enum|actor|typealias|protocol)\s+[A-Za-z_][A-Za-z0-9_]*/);
      tn=substr(line, RSTART, RLENGTH); sub(/^[a-z]+\s+/, "", tn);
      print tn "\t" $1
    }' | sort | awk -F'\t' '{
      if (!(seen[$1])) { seen[$1] = $2 } else if (seen[$1] != $2 && printed[$1]++ == 0) { print $1 ": " seen[$1] " + " $2 }
    }')
if [ -n "$dupes" ]; then
  echo "✗ duplicate top-level type declarations:" >&2
  echo "$dupes" >&2
  echo "Move the duplicates into a single file or rename one." >&2
  exit 1
fi
```

**Tests:** create a test fixture with two files both declaring `struct Foo` → hook exits nonzero. Remove one → hook exits zero.

- [ ] Hook script + test
- [ ] settings.json wiring
- [ ] Commit: `build(hooks): pre-commit refuses duplicate top-level Swift types`

---

## Task 9: Wiki — how to update goldens deliberately

**Scope:** A wiki page explaining:
- What characterization does and doesn't guarantee
- When to update a golden (deliberate behaviour change) vs when to revert (accidental regression)
- The commit pattern: `chore(golden): update <layer> after <reason>`
- The overnight-loop convention: automated agents NEVER update goldens; they revert on diff

**Files:**
- Create: `wiki/pages/characterization.md`
- Modify: `wiki/pages/project-layout.md` — add `scripts/DumpAPI/`, `Tests/__Characterization__/`

- [ ] Wiki page
- [ ] project-layout updated
- [ ] Commit: `docs(wiki): characterization page`

---

## Task 10: Tag + mark completed

- [ ] Replace `- [ ]` with `- [x]` for completed steps
- [ ] Add `Status:` line after Parent spec
- [ ] Commit: `docs(plan): mark characterization completed`
- [ ] Tag: `git tag -a v0.0.11-characterization -m "Characterization tests complete: API surface dump, document + migration goldens, engine tick traces, algo + MIDI + route goldens, characterize/verify scripts, GitHub Actions CI, no-duplicate-types pre-commit hook"`

---

## Goal-to-task traceability (self-review)

| Goal | Task |
|---|---|
| swift-syntax API dump tool | Task 1 |
| API surface goldens per module | Task 2 |
| Document + migration goldens | Task 3 |
| Engine tick-trace goldens | Task 4 |
| Algo + MIDI packet + route goldens | Task 5 |
| characterize.sh + verify-characterization.sh | Task 6 |
| GitHub Actions CI | Task 7 |
| Pre-commit: no duplicate top-level types | Task 8 |
| Wiki | Task 9 |
| Tag | Task 10 |

## Open questions resolved for this plan

- **Canonical rendering format:** indented plain text, one field per line, sorted by id where order isn't semantic. Keeps diffs readable and stable.
- **RNG determinism:** every algo test uses a seeded `SplitMix64` (helper already in the test bundle). System-RNG is never used in characterization paths.
- **Clock determinism:** engine tick-trace fixtures inject a virtual `TimeInterval` into `EngineController.tick(now:)`; real-clock paths are out of scope for characterization.
- **Legacy migration characterization:** intentional. Legacy JSON inputs pin the CURRENT decoder behaviour (whatever that is). When the reshape plan executes and changes the migration logic, the goldens will fail deliberately; the reshape plan's Task 10 will update them as part of its commits (explicit `chore(golden):` commits attributed to the reshape).
- **Who can update goldens:** any human commit. Automated agents commit with `fix(...)`, `feat(...)`, etc.; `chore(golden):` is reserved for humans (or for pre-merge confirmation sessions). Overnight loops treat any golden-failure as revert-on-regression.
- **GitHub Actions cost:** `macos-latest` minutes are expensive but zero cost for public repos. This repo is public; free tier covers the cadence.
- **Pre-commit hook scope:** `Sources/**/*.swift` only. Tests and scripts are allowed to have duplicates (e.g. mock types).
- **Tool portability:** `DumpAPI` is SPM-based and uses swift-syntax 510+ — both cross-platform. API characterization layer works in xcodebuild-less sandboxes (codex's case). The other layers require xcodebuild.
- **Waveform / audio characterization:** explicitly out of scope. Audio is a render-time concern; event-trace characterization pins the upstream.
- **Overnight refactor integration:** a follow-up plan ("Overnight Refactor Loop") wires `verify-characterization.sh` into a post-commit BT hook. This plan just ships the goldens + scripts; the refactor-loop plan wires them into the BT.
