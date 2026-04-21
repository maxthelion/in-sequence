# UI Typography + Metrics Tokens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the repeated inline SwiftUI styling recipes (font size/weight/design triples, corner radii, opacity values, spacing values) into named tokens under `Sources/UI/Theme/`. Migrate the current callsites so the same visual output renders through tokens rather than inline constants. Establish the house style as data, not per-file string-copy.

**Architecture:** Three new token families sit alongside the existing `StudioTheme` color tokens under `Sources/UI/Theme/`:

- `StudioTypography` — a `CaseIterable` enum of named font recipes (`.eyebrow`, `.label`, `.body`, `.title`, …) each carrying its size + weight + design. Applied via `Text(…).studioText(.body)` modifier.
- `StudioMetrics` — nested `enum CornerRadius { static let panel: CGFloat = 18 … }` and `enum Spacing { … }`. Applied directly as typed constants: `RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel)`.
- `StudioOpacity` — semantic `static let` values: `.subtleFill = 0.03`, `.hoverFill = 0.08`, etc. Applied directly: `Color.white.opacity(StudioOpacity.subtleFill)`.

No visual change is intended. This is a pure refactor — the output pixel-for-pixel matches main. Verification is manual visual parity against the pre-refactor build on the three main surfaces (Tracks Matrix, Phrase Workspace, Track Source), plus the existing test suite staying green.

**Tech Stack:** Swift 5.9+, SwiftUI, XCTest. No new dependencies.

**Parent spec:** None — this is a standalone code-hygiene plan. See `docs/plans/2026-04-21-per-track-owned-clips-opt-in-generators.md` for the automation workflow; this plan is not on that workflow's critical path.

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. After adding files under `Sources/UI/Theme/`, run `xcodegen generate` to register them in the project.

**Status:** Not started. Tag `v0.0.18-ui-tokens` at completion.

**Depends on:** nothing. Can be executed against current `main`.

**Deliberately deferred:**

- Light-mode / high-contrast / user-selectable themes. The tokens are static values; theme propagation via `@Environment(\.studioTheme)` is a later step if themes become a feature.
- `ButtonStyle` / `LabelStyle` role extraction (primary / ghost / toggle / badge). Rule-of-three applies — we'll see the patterns more clearly after token extraction exposes them. Not in this plan.
- A `studioShape(_:)` modifier wrapper. Direct use of `StudioMetrics.CornerRadius.panel` reads fine and is what SwiftUI's existing API takes; a wrapper would be speculative.
- Oddball corner radii (4, 5, 6, 22, 28, 30) that appear 1–4 times. Reviewed case-by-case in Task 3; bent into the token system only if they match a role, otherwise left as literals.
- Automatic enforcement via the adversarial-reviewer. Adding a rule that flags new `.font(.system(size: …))` literals is a follow-up — implement tokens first, then flag drift.

---

## Measured starting point

Current repetition census (from `Sources/UI/**.swift`):

### Typography recipes with ≥ 4 uses

| Count | Recipe | Proposed token |
|---|---|---|
| 15 | `size: 11, weight: .semibold, design: .rounded` | `.eyebrow` |
| 14 | `size: 12, weight: .medium, design: .rounded` | `.label` |
| 11 | `size: 13, weight: .medium, design: .rounded` | `.body` |
| 10 | `size: 12, weight: .bold, design: .rounded` | `.labelBold` |
| 8 | `size: 11, weight: .bold, design: .rounded` | `.eyebrowBold` |
| 7 | `size: 10, weight: .bold, design: .rounded` | `.micro` |
| 6 | `size: 14, weight: .bold, design: .rounded` | `.subtitle` |
| 6 | `size: 13, weight: .semibold, design: .rounded` | `.bodyEmphasis` |
| 4 | `size: 28, weight: .bold, design: .rounded` | `.display` |
| 4 | `size: 18, weight: .bold, design: .rounded` | `.title` |
| 4 | `size: 14, weight: .medium, design: .rounded` | `.subtitleMuted` |
| 4 | `size: 13, weight: .bold, design: .rounded` | `.bodyBold` |
| 4 | `size: 12, weight: .bold` *(no `.rounded`)* | `.chromeLabel` — investigate whether missing `.rounded` is intentional |

Under-4 recipes stay inline unless Task 2 surfaces a natural cluster.

### Corner radii

| Count | Value | Proposed role | Token |
|---|---|---|---|
| 27 | 18 | Outer panel | `CornerRadius.panel` |
| 13 | 16 | Sub-panel / group | `CornerRadius.subPanel` |
| 11 | 14 | Tile | `CornerRadius.tile` |
| 5 | 10 | Chip / pill | `CornerRadius.chip` |
| 4 | 12 | Inspect case-by-case; likely `chip` or `tile` | — |
| 4 | 22 | Inspect — probably hero chrome | — |
| 3 | 8 | Badge | `CornerRadius.badge` |
| 2 | 6, 5, 4, 28, 30 | Inspect; leave inline if truly one-off | — |

### Opacities

| Count | Value | Proposed semantic |
|---|---|---|
| 25 | 0.03 | `subtleFill` |
| 18 | 0.04 | `subtleFillAlt` (or unify with `subtleFill` if visually indistinct — decide in Task 4) |
| 9 | 0.16 | `hoverFill` |
| 6 | 0.18 | `selectedFill` |
| 5 | 0.55 | `accentFill` |
| 5 | 0.5 | `ghostStroke` |
| 5 | 0.45 | `mediumStroke` |
| 5 | 0.28 | `subtleStroke` |
| 5 | 0.2 | `softStroke` |
| 5 | 0.14 | `faintStroke` |
| 5 | 0.08 | `borderFaint` |
| 5 | 0.06 | `borderSubtle` |

Twelve opacity values with 5+ uses each — high return on semantic naming.

---

## File Structure

```
Sources/UI/Theme/
  StudioTheme.swift              # UNCHANGED — existing color tokens
  StudioTypography.swift         # NEW — font recipe enum + .studioText(_:) modifier
  StudioMetrics.swift            # NEW — CornerRadius + Spacing nested enums
  StudioOpacity.swift            # NEW — semantic opacity constants
  StudioPanel.swift              # MODIFIED — use new tokens internally
  StudioMetricPill.swift         # MODIFIED — use new tokens internally
  StudioPlaceholderTile.swift    # MODIFIED — use new tokens internally

Sources/UI/                      # MIGRATED (~30 files)
  Migrate top-of-census callsites
  to tokens. Ordered by feature dir
  so each commit is a focused diff.

Tests/SequencerAITests/UI/       # NEW test file
  StudioTypographyTests.swift    # Token equality + ordering smoke tests
```

---

## Task 1: Add `StudioTypography` enum + `.studioText(_:)` modifier

Extract the font recipes. Add a named enum token per recipe with ≥ 4 uses. Provide a SwiftUI modifier that applies the matching font.

**Files:**
- Create: `Sources/UI/Theme/StudioTypography.swift`
- Test: `Tests/SequencerAITests/UI/StudioTypographyTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/SequencerAITests/UI/StudioTypographyTests.swift`:

```swift
import Foundation
import SwiftUI
import XCTest
@testable import SequencerAI

final class StudioTypographyTests: XCTestCase {
    func test_all_recipes_declare_rounded_design_except_chrome_label() {
        for style in StudioTypography.allCases where style != .chromeLabel {
            XCTAssertEqual(style.design, .rounded, "\(style) must use .rounded design to match house style")
        }
    }

    func test_recipe_sizes_match_measured_census() {
        XCTAssertEqual(StudioTypography.eyebrow.size, 11)
        XCTAssertEqual(StudioTypography.label.size, 12)
        XCTAssertEqual(StudioTypography.body.size, 13)
        XCTAssertEqual(StudioTypography.subtitle.size, 14)
        XCTAssertEqual(StudioTypography.title.size, 18)
        XCTAssertEqual(StudioTypography.display.size, 28)
    }

    func test_weights_match_measured_census() {
        XCTAssertEqual(StudioTypography.eyebrow.weight, .semibold)
        XCTAssertEqual(StudioTypography.labelBold.weight, .bold)
        XCTAssertEqual(StudioTypography.body.weight, .medium)
        XCTAssertEqual(StudioTypography.bodyEmphasis.weight, .semibold)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/StudioTypographyTests \
  2>&1 | tail -10
```

Expected: compile failure — `StudioTypography` does not exist.

- [ ] **Step 3: Create the enum + modifier**

Write `Sources/UI/Theme/StudioTypography.swift`:

```swift
import SwiftUI

enum StudioTypography: String, CaseIterable, Sendable {
    case eyebrow            // 11 / semibold / rounded
    case eyebrowBold        // 11 / bold     / rounded
    case label              // 12 / medium   / rounded
    case labelBold          // 12 / bold     / rounded
    case body               // 13 / medium   / rounded
    case bodyBold           // 13 / bold     / rounded
    case bodyEmphasis       // 13 / semibold / rounded
    case micro              // 10 / bold     / rounded
    case subtitle           // 14 / bold     / rounded
    case subtitleMuted      // 14 / medium   / rounded
    case title              // 18 / bold     / rounded
    case display            // 28 / bold     / rounded
    case chromeLabel        // 12 / bold     / (system design)

    var size: CGFloat {
        switch self {
        case .micro: return 10
        case .eyebrow, .eyebrowBold: return 11
        case .label, .labelBold, .chromeLabel: return 12
        case .body, .bodyBold, .bodyEmphasis: return 13
        case .subtitle, .subtitleMuted: return 14
        case .title: return 18
        case .display: return 28
        }
    }

    var weight: Font.Weight {
        switch self {
        case .eyebrow, .bodyEmphasis: return .semibold
        case .label, .body, .subtitleMuted: return .medium
        case .eyebrowBold, .labelBold, .bodyBold, .micro, .subtitle, .title, .display, .chromeLabel: return .bold
        }
    }

    var design: Font.Design {
        switch self {
        case .chromeLabel: return .default
        default: return .rounded
        }
    }

    var font: Font {
        .system(size: size, weight: weight, design: design)
    }
}

extension View {
    func studioText(_ style: StudioTypography) -> some View {
        self.font(style.font)
    }
}
```

- [ ] **Step 4: Regenerate the xcodeproj**

```bash
xcodegen generate
```

Expected: writes the project including the new file.

- [ ] **Step 5: Run test to verify it passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/StudioTypographyTests \
  2>&1 | tail -10
```

Expected: three tests pass.

- [ ] **Step 6: Full suite stays green**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -10
```

Expected: all tests pass. No existing test should break — the new file only adds symbols.

- [ ] **Step 7: Commit**

```bash
git add Sources/UI/Theme/StudioTypography.swift Tests/SequencerAITests/UI/StudioTypographyTests.swift project.yml
git commit -m "feat(ui): StudioTypography enum + .studioText modifier"
```

---

## Task 2: Migrate typography callsites to `.studioText(_:)`

Walk the repo replacing the 13 recipes measured in the census with the corresponding `.studioText(_:)` call. Start with `Sources/UI/Theme/` (the shared components so downstream code inherits the new style for free), then proceed feature-dir by feature-dir.

**Files:** every file that currently contains one of the 13 measured recipes. Approximate list from the census: 18–20 files under `Sources/UI/`.

- [ ] **Step 1: Replace all uses of the size-11 semibold recipe (15 callsites)**

Pattern to replace:
```swift
.font(.system(size: 11, weight: .semibold, design: .rounded))
```

Replace with:
```swift
.studioText(.eyebrow)
```

Use Grep to find, then Edit to replace one-by-one. Do not combine with any other refactor.

- [ ] **Step 2: Build to verify no type errors**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -10
```

Expected: build succeeds.

- [ ] **Step 3: Commit the first recipe migration**

```bash
git add Sources/UI
git commit -m "refactor(ui): migrate size-11 semibold font to .studioText(.eyebrow)"
```

- [ ] **Step 4: Repeat steps 1–3 for each remaining recipe**

Order by frequency (highest first). One commit per recipe so reverts stay surgical:

1. `size: 12, weight: .medium, design: .rounded` → `.studioText(.label)` (14 callsites)
2. `size: 13, weight: .medium, design: .rounded` → `.studioText(.body)` (11)
3. `size: 12, weight: .bold, design: .rounded` → `.studioText(.labelBold)` (10)
4. `size: 11, weight: .bold, design: .rounded` → `.studioText(.eyebrowBold)` (8)
5. `size: 10, weight: .bold, design: .rounded` → `.studioText(.micro)` (7)
6. `size: 14, weight: .bold, design: .rounded` → `.studioText(.subtitle)` (6)
7. `size: 13, weight: .semibold, design: .rounded` → `.studioText(.bodyEmphasis)` (6)
8. `size: 28, weight: .bold, design: .rounded` → `.studioText(.display)` (4)
9. `size: 18, weight: .bold, design: .rounded` → `.studioText(.title)` (4)
10. `size: 14, weight: .medium, design: .rounded` → `.studioText(.subtitleMuted)` (4)
11. `size: 13, weight: .bold, design: .rounded` → `.studioText(.bodyBold)` (4)
12. `size: 12, weight: .bold` *(no design)* → `.studioText(.chromeLabel)` (4) — verify that the absence of `.rounded` is intentional; if unclear, ask and leave inline.

Commit message template: `refactor(ui): migrate <recipe> font to .studioText(<token>)`.

- [ ] **Step 5: Verify the full suite passes after all migrations**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -10
```

Expected: tests pass.

- [ ] **Step 6: Visual parity check on three main surfaces**

Build and open the app:

```bash
./scripts/open-latest-build.sh
```

Navigate to:
- Tracks Matrix (top bar → "TRACKS"). Inspect: track names, destination labels, pattern-slot numbers all render at the same size/weight as main's build.
- Phrase Workspace (top bar → "PHRASE"). Inspect: layer headers, cell preview text, transport labels.
- Track Source (select a track → Source panel). Inspect: "Add Generator" button, pattern-slot palette numbers, clip name.

If anything looks different, the recipe → token mapping was wrong. Stop, diff the recipe definition against the census, fix, re-build.

---

## Task 3: Add `StudioMetrics` enum (corner radius + spacing)

Extract the corner-radius and spacing scales. Corner radius tokens are drawn from the census; spacing tokens fold the most-repeated inline numbers into a 4-step scale.

**Files:**
- Create: `Sources/UI/Theme/StudioMetrics.swift`

- [ ] **Step 1: Create the enum**

Write `Sources/UI/Theme/StudioMetrics.swift`:

```swift
import CoreGraphics

enum StudioMetrics {
    enum CornerRadius {
        static let panel: CGFloat = 18
        static let subPanel: CGFloat = 16
        static let tile: CGFloat = 14
        static let chip: CGFloat = 10
        static let badge: CGFloat = 8
    }

    enum Spacing {
        static let tight: CGFloat = 6
        static let snug: CGFloat = 8
        static let standard: CGFloat = 14
        static let loose: CGFloat = 18
    }
}
```

- [ ] **Step 2: Regenerate + build**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -5
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/Theme/StudioMetrics.swift project.yml
git commit -m "feat(ui): StudioMetrics enum (corner radius + spacing tokens)"
```

---

## Task 4: Migrate corner radii to `StudioMetrics.CornerRadius`

Migrate by radius role, commit each cluster separately. For oddball radii (4, 5, 6, 22, 28, 30), inspect the callsite: if it matches an existing role, promote to that token; otherwise leave the literal with a one-line comment explaining why.

**Files:** ~20 files currently using `cornerRadius: N` literals.

- [ ] **Step 1: Migrate `cornerRadius: 18` → `StudioMetrics.CornerRadius.panel` (27 callsites)**

Grep for `cornerRadius: 18`, Edit each to `cornerRadius: StudioMetrics.CornerRadius.panel`.

- [ ] **Step 2: Build, commit**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -5
git add Sources/UI
git commit -m "refactor(ui): panel corner radius → StudioMetrics.CornerRadius.panel"
```

- [ ] **Step 3: Repeat for the remaining roles**

Each as its own commit:
- `cornerRadius: 16` → `.subPanel` (13)
- `cornerRadius: 14` → `.tile` (11)
- `cornerRadius: 10` → `.chip` (5)
- `cornerRadius: 8` → `.badge` (3)

Commit message template: `refactor(ui): <role> corner radius → StudioMetrics.CornerRadius.<token>`.

- [ ] **Step 4: Audit the oddballs (4, 5, 6, 12, 22, 28, 30)**

For each remaining literal corner radius, Read the callsite's ~20-line context. Decide:

- If it's semantically the same role as an existing token (e.g., a `12` that's clearly acting as a chip): migrate and commit under that role.
- If it's a true one-off (e.g., a 28-radius hero card with no siblings): leave the literal, add a one-line comment `// Hero chrome — intentionally distinct from panel/subPanel.`

Commit this audit pass once complete:
```bash
git commit -m "refactor(ui): audit oddball corner radii; promote or annotate"
```

- [ ] **Step 5: Full suite passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: tests pass. Visual parity check on the same three surfaces from Task 2 Step 6.

---

## Task 5: Add `StudioOpacity` semantic constants + migrate

Corner radii and typography have natural multi-enum structure; opacity values are single scalars but the semantic intent is more important than the number. A flat `enum StudioOpacity` with named static constants makes intent first-class.

**Files:**
- Create: `Sources/UI/Theme/StudioOpacity.swift`
- Modify: ~20 files currently using `.opacity(0.0X)` literals in role-consistent ways.

- [ ] **Step 1: Create the enum**

Write `Sources/UI/Theme/StudioOpacity.swift`:

```swift
import CoreGraphics

enum StudioOpacity {
    // Fills — background tints layered onto panel/tile chrome.
    static let subtleFill: CGFloat = 0.03
    static let hoverFill: CGFloat = 0.16
    static let selectedFill: CGFloat = 0.18
    static let accentFill: CGFloat = 0.55

    // Strokes — border alphas.
    static let borderSubtle: CGFloat = 0.06
    static let borderFaint: CGFloat = 0.08
    static let faintStroke: CGFloat = 0.14
    static let softStroke: CGFloat = 0.2
    static let subtleStroke: CGFloat = 0.28
    static let mediumStroke: CGFloat = 0.45
    static let ghostStroke: CGFloat = 0.5
}
```

Note: the census distinguished 0.03 (25×) and 0.04 (18×). They are visually near-identical on the intended chrome backgrounds; Step 3 below collapses 0.04 → 0.03 intentionally. Audit during Task 5 Step 4 to confirm no callsite depends on the distinction.

- [ ] **Step 2: Regenerate + build, commit**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS' 2>&1 | tail -5
git add Sources/UI/Theme/StudioOpacity.swift project.yml
git commit -m "feat(ui): StudioOpacity semantic opacity constants"
```

- [ ] **Step 3: Migrate the 12 highest-count opacity values**

Each its own commit, same pattern as Tasks 2 and 4:

- `.opacity(0.03)` → `.opacity(StudioOpacity.subtleFill)` (25 callsites)
- `.opacity(0.04)` → `.opacity(StudioOpacity.subtleFill)` (18 — unify with 0.03)
- `.opacity(0.16)` → `.opacity(StudioOpacity.hoverFill)` (9)
- `.opacity(0.18)` → `.opacity(StudioOpacity.selectedFill)` (6)
- `.opacity(0.55)` → `.opacity(StudioOpacity.accentFill)` (5)
- `.opacity(0.5)` → `.opacity(StudioOpacity.ghostStroke)` (5)
- `.opacity(0.45)` → `.opacity(StudioOpacity.mediumStroke)` (5)
- `.opacity(0.28)` → `.opacity(StudioOpacity.subtleStroke)` (5)
- `.opacity(0.2)` → `.opacity(StudioOpacity.softStroke)` (5)
- `.opacity(0.14)` → `.opacity(StudioOpacity.faintStroke)` (5)
- `.opacity(0.08)` → `.opacity(StudioOpacity.borderFaint)` (5)
- `.opacity(0.06)` → `.opacity(StudioOpacity.borderSubtle)` (5)

For each: Grep, Edit per callsite, build, commit. Do not combine.

Commit template: `refactor(ui): <value> opacity → StudioOpacity.<token>`.

- [ ] **Step 4: Verify the 0.04 → subtleFill collapse is visually indistinguishable**

Open the app:

```bash
./scripts/open-latest-build.sh
```

Focus on the callsites that previously used `0.04`. If any look visually different from main, back out the unification and keep `subtleFillAlt: 0.04` as a separate token.

- [ ] **Step 5: Full suite passes**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: tests pass. Visual parity check on the same three surfaces.

---

## Task 6: Migrate shared-chrome files and verify

The primary consumers of these tokens are `Sources/UI/Theme/StudioPanel.swift`, `StudioMetricPill.swift`, `StudioPlaceholderTile.swift`. Earlier tasks migrated these files as part of the per-recipe sweeps. This task audits them to confirm they read entirely through tokens, with no remaining inline style literals.

**Files:**
- Audit: `Sources/UI/Theme/StudioPanel.swift`
- Audit: `Sources/UI/Theme/StudioMetricPill.swift`
- Audit: `Sources/UI/Theme/StudioPlaceholderTile.swift`

- [ ] **Step 1: Grep each file for remaining literal-style patterns**

For each file, run Grep with patterns:
- `.font(.system(size:`
- `cornerRadius: [0-9]`
- `.opacity(0\.[0-9]`

Any match is a missed migration. Read the callsite, pick the correct token, Edit.

- [ ] **Step 2: Commit if any fixes were made**

```bash
git add Sources/UI/Theme
git commit -m "refactor(ui): complete theme-file migration to tokens"
```

- [ ] **Step 3: Final test + visual check**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -10
```

Expected: tests pass.

Open the app one more time, verify the three main surfaces. If they match the pre-refactor build, proceed to tag.

---

## Task 7: Update plan status, tag, and flag follow-ups

**Files:**
- Modify: `docs/plans/2026-04-21-ui-typography-metrics-tokens.md` (this plan) — set Status to Completed.

- [ ] **Step 1: Flip the Status line**

Replace `**Status:** Not started.` with `**Status:** ✅ Completed 2026-04-21. Tag v0.0.18-ui-tokens.`

- [ ] **Step 2: Commit, tag**

```bash
git add docs/plans/2026-04-21-ui-typography-metrics-tokens.md
git commit -m "docs(plan): mark ui-typography-metrics-tokens completed"
git tag -a v0.0.18-ui-tokens -m "UI token extraction: StudioTypography, StudioMetrics, StudioOpacity + ~60 callsite migrations"
```

- [ ] **Step 3: Log follow-ups in a review-queue note**

Create `.claude/state/review-queue/followup-2026-04-21-ui-token-followups.md`:

```markdown
# Follow-ups from UI token extraction (v0.0.18-ui-tokens)

- **Adversarial-reviewer rule:** add a §1 hunt bullet that flags new `.font(.system(size:…))` / `cornerRadius: <literal>` / `.opacity(<literal>)` in UI code. Tokens exist; drift should be called out.
- **ButtonStyle extraction:** several reused button recipes (Add Generator, Remove, bypass badge, clip picker) could promote to named `ButtonStyle` types once the rule-of-three threshold is clearly crossed. Not yet.
- **Theme propagation:** if light-mode or high-contrast ever ship, `StudioTheme` / `StudioTypography` / etc. should move behind `@Environment(\.studioTheme)` or similar. Current static `enum` shape is fine until then.
- **0.04 opacity collapse:** if Task 5 Step 4 kept `subtleFillAlt` separate, the 18 callsites using it should be revisited after a design pass — the distinction may or may not still matter.
```

Commit:
```bash
git add .claude/state/review-queue/followup-2026-04-21-ui-token-followups.md
git commit -m "chore(state): record UI token follow-ups"
```

---

## Self-Review

**Spec coverage:** This plan doesn't have an external spec; the "spec" is the census table in the Measured starting point section. Each census row has a corresponding task step. ✓

**Placeholder scan:** Every step has an exact command, an exact replacement pattern, or an explicit audit instruction. No TBDs. ✓

**Type consistency:** `StudioTypography`, `StudioMetrics.CornerRadius`, `StudioMetrics.Spacing`, `StudioOpacity` named identically across tasks. The modifier is `.studioText(_:)` everywhere. ✓

**Scope check:** One plan, ~40 files touched, mechanical refactor. Visual parity is the success gate. Committed per-role so reverts stay surgical. Doesn't try to swallow `ButtonStyle` extraction or theme propagation. ✓

**Risk:** Visual regressions. Mitigation: per-recipe commits + mandatory visual parity checks at Tasks 2, 4, 5 Step 4, and Task 6.
