# QA Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give this project a working visual-QA loop: snapshot tests for SwiftUI views (regression gate), one XCUITest "screens tour" target that produces a PNG per primary screen, a shell script that runs the tour and dumps outputs to `docs/screenshots/`, and a session-start hook that tells a fresh Claude those screenshots exist as orientation. Verified by: running `bash scripts/screenshot-all.sh` produces N PNGs in `docs/screenshots/`; `xcodebuild test` passes with snapshot baselines in place; a fresh Claude session's banner mentions the latest screenshot dir.

**Architecture:** Two separable pieces. (1) **Snapshot tests** via `swift-snapshot-testing` (pointfreeco) — cheap, per-view, runs on every `xcodebuild test`, stores baseline PNGs under `Tests/__Snapshots__/`, fails CI on pixel diff. (2) **Screens-tour XCUITest target** — one XCUITest that launches the real app, navigates through every primary workspace (Tracks matrix, Phrase grid per layer, Track detail per type, Mixer, Perform overlay, Preferences), and calls `XCUIScreen.main.screenshot()` at each stop, attaching to the test report AND optionally writing to a disk directory the script scrapes. Separate from the snapshot tests so one can run fast (snapshot) while the other runs slow (tour).

**Tech Stack:** Swift 5.9+, XCTest, XCUITest, `swift-snapshot-testing` 1.15+ (package dependency), Bash 3.2 (macOS default), `xcodebuild`, `xcrun`. No JavaScript / Node / third-party MCP dependencies.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` — §"UX surfaces" (the screens-tour covers each listed view). This plan is cross-cutting infrastructure rather than a sub-spec implementation.

**Environment note:** Xcode 16 at `/Applications/Xcode.app`. `xcode-select` points at CommandLineTools. All `xcodebuild` invocations in this plan prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. XCUITest requires a real macOS runner (headless OK; no simulator needed since this is a macOS app).

**Status:** <STATUS_PREFIX> <COMPLETED_MARKER> TBD. Tag `v0.0.4-qa-infra` at TBD.

**Deliberately deferred (not in this plan):**

- **CI pipeline integration** (GitHub Actions YAML, baseline-update PR workflow). Separate plan.
- **Accessibility audit automation** (`XCUIApplication.performAccessibilityAudit()`). Covered by a follow-up plan once the primary screens stabilise.
- **Snapshot in dark mode** — land light mode first; dark-mode baselines arrive after the theme work in a follow-up plan.
- **Claude / MCP integration** — exposing screenshots as an MCP tool for an agent to consume. Deferred; the shell-script output is already consumable by the agent via `Read` on the generated PNGs, which is enough to start with.

---

## File Structure

```
Package.swift                             # MODIFIED — add swift-snapshot-testing dep
project.yml                               # MODIFIED — add SequencerAIScreensUITests target
Sources/UI/                               # MODIFIED — add accessibilityIdentifier(_:) on
                                          # the nav-worthy views the screens-tour targets
Tests/
  SequencerAITests/
    Snapshots/                            # NEW — per-view snapshot tests
      PhraseWorkspaceSnapshotTests.swift
      StudioTopBarSnapshotTests.swift
      TrackDetailSnapshotTests.swift
      ...
    __Snapshots__/                        # NEW — swift-snapshot-testing baselines (committed)
      PhraseWorkspaceSnapshotTests/
        test_phrase_matrix_pattern_layer.1.png
        test_phrase_matrix_volume_layer.1.png
      ...
  SequencerAIScreensUITests/              # NEW XCUITest target
    ScreensTourTests.swift                # one test that navigates every screen and shots
    ScreenCapture.swift                   # helper that writes screenshots to SCREENSHOT_OUT_DIR
scripts/
  screenshot-all.sh                       # NEW — wraps xcodebuild test invocation; output to docs/screenshots/
docs/
  screenshots/                            # NEW — last-generated PNGs, committed so a fresh land sees them
    README.md                             # what's in this dir, how to regenerate
    studio-chrome.png
    phrase-matrix-pattern-layer.png
    phrase-matrix-volume-layer.png
    track-detail-mono-melodic.png
    track-detail-drum.png
    mixer.png
    perform-overlay.png
    preferences.png
.claude/hooks/session-start.sh            # MODIFIED — the banner mentions the screenshot dir
```

---

## Task 1: Add `swift-snapshot-testing` package dependency

**Scope:** Add pointfreeco/swift-snapshot-testing to the xcodegen project. Verify it resolves by building the project. Does not yet write any snapshot tests.

**Files:**
- Modify: `project.yml` (add package + link to test target)
- Verify: `SequencerAI.xcodeproj` regenerates cleanly after `xcodegen generate`

**project.yml change (fragment):**

```yaml
packages:
  SnapshotTesting:
    url: https://github.com/pointfreeco/swift-snapshot-testing
    from: "1.15.0"

targets:
  SequencerAITests:
    dependencies:
      - package: SnapshotTesting
        product: SnapshotTesting
      # ...existing deps stay
```

**Tests:**

1. After `xcodegen generate`, the test target links against `SnapshotTesting` (confirm by trying an `import SnapshotTesting` in any test file — compile succeeds).
2. `DEVELOPER_DIR=... xcodebuild -resolvePackageDependencies` succeeds and pins the version.

- [ ] Edit `project.yml`
- [ ] Run `xcodegen generate`
- [ ] Add a throwaway `import SnapshotTesting` line to an existing test file; run `xcodebuild build-for-testing`; verify success; remove the line
- [ ] Commit: `build(deps): add swift-snapshot-testing 1.15+`

---

## Task 2: Write a first snapshot test — `StudioTopBar`

**Scope:** Smallest possible view first. Prove the snapshot pipeline works end-to-end: record a baseline, see it saved under `__Snapshots__`, re-run to verify it matches.

**Files:**
- Create: `Tests/SequencerAITests/Snapshots/StudioTopBarSnapshotTests.swift`
- Will create on first run: `Tests/SequencerAITests/__Snapshots__/StudioTopBarSnapshotTests/test_default.1.png` (committed afterwards)

**Test shape:**

```swift
import XCTest
import SnapshotTesting
import SwiftUI
@testable import SequencerAI

final class StudioTopBarSnapshotTests: XCTestCase {
    func test_default() {
        let view = StudioTopBar(
            document: .constant(SeqAIDocument()),
            section: .constant(.phrase)
        )
        .frame(width: 1200, height: 80)
        assertSnapshot(of: NSHostingView(rootView: view), as: .image(size: CGSize(width: 1200, height: 80)))
    }
}
```

**Tests:**

1. First run: expected to fail with "No reference found — recording new snapshot." PNG appears under `Tests/SequencerAITests/__Snapshots__/StudioTopBarSnapshotTests/test_default.1.png`.
2. Second run (against the recorded baseline): passes.
3. Modify the view deliberately (e.g. change a hard-coded string); re-run — test fails with a diff. Revert the change; green again.

- [ ] Write the test
- [ ] Run it — capture the recorded baseline
- [ ] Commit baseline PNG alongside the test file
- [ ] Run it again — green
- [ ] Commit: `test(ui): StudioTopBar snapshot baseline`

---

## Task 3: Snapshot tests for the core SwiftUI views

**Scope:** One snapshot test per primary view; one assertion per *significant state*. Don't exhaustively cover everything — pick the states that would be embarrassing to break.

Primary views to cover (existing in codex-merged code):

- `StudioTopBar` — Task 2 ✓
- `ContentView` — top-level shell in `.song`, `.phrase`, `.track`, `.mixer` section states (4 snapshots)
- `PhraseWorkspaceView` — matrix-visible with 4 tracks, Pattern layer selected; then Volume layer selected; then Intensity layer selected. (3 snapshots)
- `DetailView` — for a `.instrument` track with a step pattern; for a `.drumRack` track with per-tag rows; for a `.sliceLoop` track stub (3 snapshots)
- `MixerView` — with 3 tracks (1 snapshot)
- `StepGridView` — mono step pattern, 8 filled steps (1 snapshot)
- `TransportBar` — stopped state; playing state (2 snapshots)
- `WorkspaceSection` — each of its 4 states if distinct (4 snapshots)
- `PreferencesView` — default state (1 snapshot)

Total: ~20 snapshot tests. Each test owns a small fixture function that constructs the view with deterministic data (no `Date()`, no randomness, no external MIDI).

**Files:**
- Create: one `*SnapshotTests.swift` file per primary view
- Commit all baseline PNGs under `Tests/SequencerAITests/__Snapshots__/<TestClass>/`

**Fixture helper (shared across tests):**

```swift
// Tests/SequencerAITests/Snapshots/Fixtures.swift
enum SnapshotFixtures {
    static let threeTrackDocument: SeqAIDocument = {
        var doc = SeqAIDocument()
        doc.model.tracks = [
            StepSequenceTrack.mock(name: "Kick", type: .drumRack),
            StepSequenceTrack.mock(name: "Bass", type: .instrument),
            StepSequenceTrack.mock(name: "Lead", type: .instrument)
        ]
        doc.model.selectedTrackID = doc.model.tracks[0].id
        return doc
    }()
    // ... more fixtures
}
```

**Tests:** each view's test file contains 1-4 `test_*` methods, each asserting a snapshot of one state.

- [ ] Write all snapshot tests, one view at a time; record baseline; verify green on re-run; commit baseline
- [ ] Full suite run green
- [ ] Commit: `test(ui): snapshot baselines for primary views`

Recommend breaking this into **several commits** by view so the reviewer can follow.

---

## Task 4: Add accessibility identifiers to the nav-worthy views

**Scope:** XCUITest (Task 6) needs stable handles on UI elements to navigate through. Ad-hoc string-matching on button labels is brittle. Add `.accessibilityIdentifier(_:)` to each view the screens-tour needs to click or verify.

**Identifiers to add:**

- Studio chrome buttons: `"section-song"`, `"section-phrase"`, `"section-track"`, `"section-mixer"`, `"section-perform"`, `"section-library"`, `"section-preferences"`
- Transport: `"transport-play"`, `"transport-stop"`
- Phrase matrix: `"phrase-row-\(phraseID)"` per phrase row, `"layer-selector-\(layerName)"` per layer tab
- Track matrix (when it lands): `"track-card-\(trackID)"`
- Pattern strip (when it lands): `"pattern-slot-\(index)"`

For Task 6 to work on the current codebase, covering the chrome section buttons and transport is enough — phrase / track / pattern identifiers can land as those workspaces grow.

**Files:**
- Modify: `Sources/UI/StudioTopBar.swift`, `Sources/UI/TransportBar.swift`, `Sources/UI/PhraseWorkspaceView.swift`, `Sources/UI/DetailView.swift`, `Sources/UI/MixerView.swift`, `Sources/UI/ContentView.swift`

**Tests:**

- No new unit tests — Task 6's XCUITest queries these identifiers, so failure surfaces there. But: add one tiny XCTest that instantiates each view and pokes the accessibility tree via `NSHostingView`'s `accessibilityElement` tree, asserting each identifier is present. This saves the slow-feedback XCUITest iteration.

- [ ] Add identifiers in all above files
- [ ] Write a fast `AccessibilityIdentifiersTests.swift` that walks views and asserts each expected ID is reachable
- [ ] Green
- [ ] Commit: `feat(ui): accessibility identifiers for nav-worthy views`

---

## Task 5: New XCUITest target `SequencerAIScreensUITests`

**Scope:** Set up the UI test target in `project.yml`. Verify an empty test class runs. No actual tour logic yet — just infrastructure.

**Files:**
- Modify: `project.yml` (add a new UI-test target)
- Create: `Tests/SequencerAIScreensUITests/Placeholder.swift` with one empty test

**project.yml fragment:**

```yaml
targets:
  SequencerAIScreensUITests:
    type: bundle.ui-testing
    platform: macOS
    sources:
      - Tests/SequencerAIScreensUITests
    dependencies:
      - target: SequencerAI
    settings:
      base:
        TEST_TARGET_NAME: SequencerAI
```

**Test:**

```swift
final class PlaceholderTests: XCTestCase {
    func test_app_launches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.waitForExistence(timeout: 5))
        app.terminate()
    }
}
```

**Tests:**

1. `DEVELOPER_DIR=... xcodebuild test -scheme SequencerAI -only-testing:SequencerAIScreensUITests/PlaceholderTests` — succeeds in under 30 seconds.

- [ ] project.yml update
- [ ] `xcodegen generate`
- [ ] Placeholder test runs green
- [ ] Commit: `build: SequencerAIScreensUITests target scaffold`

---

## Task 6: Screens-tour test — `ScreensTourTests`

**Scope:** One XCUITest method per primary screen. Each method:
1. Launches the app (or reuses state across tests — prefer independence for reliability)
2. Navigates to the target screen via accessibility identifiers from Task 4
3. Takes a screenshot via `XCUIScreen.main.screenshot()` (the full primary screen) or `app.windows.firstMatch.screenshot()` (just the app window)
4. Attaches it to the test report AND writes it to the environment-variable-specified output directory (read `SCREENSHOT_OUT_DIR` from `ProcessInfo`)

**Files:**
- Create: `Tests/SequencerAIScreensUITests/ScreenCapture.swift` (helper)
- Create: `Tests/SequencerAIScreensUITests/ScreensTourTests.swift` (one test per screen)

**Helper:**

```swift
// Tests/SequencerAIScreensUITests/ScreenCapture.swift
import XCTest

enum ScreenCapture {
    static func capture(_ app: XCUIApplication, name: String) {
        let window = app.windows.firstMatch
        let screenshot = window.screenshot()
        // Attach to test report
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "screenshot: \(name)") { activity in
            activity.add(attachment)
        }
        // Write to disk if SCREENSHOT_OUT_DIR is set
        if let outDir = ProcessInfo.processInfo.environment["SCREENSHOT_OUT_DIR"] {
            let url = URL(fileURLWithPath: outDir).appendingPathComponent("\(name).png")
            try? screenshot.pngRepresentation.write(to: url)
        }
    }
}
```

**Tests (one `test_screen_*` per primary screen):**

```swift
final class ScreensTourTests: XCTestCase {
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDown() {
        app.terminate()
    }

    func test_screen_song() {
        app.buttons["section-song"].click()
        ScreenCapture.capture(app, name: "song")
    }

    func test_screen_phrase_pattern_layer() {
        app.buttons["section-phrase"].click()
        app.buttons["layer-selector-Pattern"].click()
        ScreenCapture.capture(app, name: "phrase-matrix-pattern-layer")
    }

    // ... one test per primary screen
}
```

Cover these at minimum (expand as workspaces land):

- `song`
- `phrase-matrix-pattern-layer`
- `phrase-matrix-volume-layer`
- `phrase-matrix-intensity-layer`
- `track-detail-instrument`
- `track-detail-drumrack`
- `track-detail-sliceloop`
- `mixer`
- `perform`
- `preferences`

**Tests:**

1. Each test runs in isolation (fresh app launch) in under 15 seconds.
2. `xcodebuild test -scheme SequencerAI -only-testing:SequencerAIScreensUITests/ScreensTourTests` succeeds and attaches N screenshots to the test report.
3. Running with `SCREENSHOT_OUT_DIR=/tmp/shots xcodebuild test ...` writes N PNGs to `/tmp/shots/`.
4. A screen whose identifiers don't exist in the current codebase is SKIPPED with an XCTSkip (not a hard failure) — so the suite works as workspaces are added incrementally.

- [ ] Write helper + tests
- [ ] Implement each test method, skipping any that depend on unshipped screens
- [ ] Run green (with skips as appropriate)
- [ ] Commit: `test(ui): screens-tour XCUITest with per-screen screenshots`

---

## Task 7: `scripts/screenshot-all.sh`

**Scope:** Shell wrapper that runs the screens-tour with `SCREENSHOT_OUT_DIR` pointing at `docs/screenshots/`, cleans up the old PNGs first, and reports how many were written.

**File:** `scripts/screenshot-all.sh`

**Content:**

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO/docs/screenshots"

echo "🖼  Clearing $OUT/*.png"
mkdir -p "$OUT"
find "$OUT" -maxdepth 1 -type f -name '*.png' -delete

echo "🎬  Running screens-tour"
export SCREENSHOT_OUT_DIR="$OUT"
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test \
  -project "$REPO/SequencerAI.xcodeproj" \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAIScreensUITests/ScreensTourTests \
  > /tmp/screens-tour.log 2>&1

COUNT=$(find "$OUT" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')
echo "✅ Captured $COUNT screenshots → $OUT"
ls -la "$OUT"
```

Add executable bit. Reference from `docs/screenshots/README.md`.

**Tests:**

1. `bash scripts/screenshot-all.sh` exits 0 on a clean build.
2. `docs/screenshots/` contains N PNG files after the run (where N matches the tour's test count minus any skipped).
3. A second run leaves the same N PNG files (idempotent).

- [ ] Write script + README
- [ ] Run it manually — verify screenshots appear
- [ ] Commit: `build(scripts): screenshot-all.sh + docs/screenshots/ baseline`

---

## Task 8: Session-start hook mentions the screenshot dir

**Scope:** A fresh Claude landing in the repo should be told the screenshot set exists as visual orientation.

**File:** `.claude/hooks/session-start.sh`

**Change:** Add a line to the banner output like:

```
│ screenshots: docs/screenshots/ (N PNGs, updated <YYYY-MM-DD>)
```

Compute N by counting PNGs; compute the update date from the newest file's mtime.

**Tests:**

1. Running `.claude/hooks/session-start.sh` after Task 7 produces a banner that includes the screenshots line.
2. The count matches `ls docs/screenshots/*.png | wc -l`.
3. If `docs/screenshots/` is empty or missing, the line reads `screenshots: none yet — run scripts/screenshot-all.sh`.

- [ ] Update the hook
- [ ] Verify output
- [ ] Commit: `docs(automation): session-start banner mentions the screenshot dir`

---

## Task 9: Wiki update

**Scope:** One new page documenting the QA setup; one-liner in automation-setup referring to it.

**Files:**
- Create: `wiki/pages/qa-infrastructure.md` (short — point at the plan + scripts; link to `docs/screenshots/` and `Tests/SequencerAITests/Snapshots/`)
- Modify: `wiki/pages/automation-setup.md` (a link to the new page; brief description)

- [ ] Write wiki page
- [ ] automation-setup updated
- [ ] Commit: `docs(wiki): qa-infrastructure page + cross-reference`

---

## Task 10: Tag + mark completed

- [ ] Replace every `- [ ]` in this file with `- [x]` for steps actually completed
- [ ] Add a `Status:` line after `Parent spec` in this file's header, following the placeholder-token pattern used in other plans
- [ ] Commit: `docs(plan): mark qa-infrastructure completed`
- [ ] Tag: `git tag -a v0.0.4-qa-infra -m "QA infrastructure complete: snapshot tests, screens-tour UI test, screenshot-all.sh, docs/screenshots/ committed, session-start banner mentions the screenshot set"`

---

## Goal-to-task traceability (self-review)

| Goal / architectural claim | Task |
|---|---|
| `swift-snapshot-testing` available as a package dep | Task 1 |
| First snapshot test proves the pipeline | Task 2 |
| Snapshot baselines for the primary SwiftUI views | Task 3 |
| Accessibility identifiers on nav-worthy views | Task 4 |
| XCUITest target exists | Task 5 |
| Screens-tour test produces N PNGs per screen | Task 6 |
| `scripts/screenshot-all.sh` dumps to `docs/screenshots/` | Task 7 |
| Session-start banner surfaces the screenshot dir | Task 8 |
| Wiki documents the workflow | Task 9 |
| Tag | Task 10 |

## Open questions resolved for this plan

- **Per-view vs per-screen scope of snapshot tests:** per-view snapshots for all reusable UI components (Task 3). Per-screen full-window snapshots are the screens-tour (Task 6). They cover different regression classes — individual-component rendering vs full-app composition — so both are worth running.
- **Dark mode baselines:** deferred. Light mode only in this plan. Dark-mode tests are trivial to add later by running the same view with `.colorScheme(.dark)` and asserting a separate baseline; doubles the baseline count.
- **Baseline update workflow:** on a deliberate UI change, the snapshot test fails and points at the diff. The fix is `rm Tests/SequencerAITests/__Snapshots__/<TestClass>/<test>.png` and re-run to record a new baseline; review the new PNG in git and commit. This is the standard `swift-snapshot-testing` workflow; document it in the wiki page.
- **Accessibility audit:** `XCUIApplication.performAccessibilityAudit()` is macOS 14+. Deferred to a follow-up plan — not blocking this one.
- **Test fixtures isolation:** snapshot tests use `SnapshotFixtures.threeTrackDocument` etc. No `Date()`, `Bool.random()`, network, or MIDI device enumeration in any snapshot test's fixture path. Dependency-injection shims added to the document-model / engine-controller code paths the snapshots touch, if they haven't already been added by codex's earlier work.
