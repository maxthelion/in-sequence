# Observability From Application Logs — Existing State

Inspected on 2026-05-03. Source files examined are listed per finding.

---

## Summary

The app already emits a small amount of runtime diagnostic output, but it is not an observability system yet. Most production paths use ad-hoc `NSLog(...)` calls, one engine path uses `Logger`, and there is no in-repo pipeline that collects application logs, fingerprints repeated failures, attaches commit provenance, or turns runtime events into actionable issues. The existing automation loops already know how to route markdown work items and critiques, but nothing bridges runtime app logs into those queues.

---

## What Exists Today

### App Log Emission

**`Sources/App/SequencerAIApp.swift`**

- Startup bootstrap failures are logged with `NSLog`, not surfaced as structured events.
- Current messages are narrow bootstrap breadcrumbs:
  - `AppSupportBootstrap failed: ...`
  - `[SequencerAIApp] sample library bootstrap failed: ...`
- The app eagerly warms shared singletons (`MIDISession.shared`, `AudioSampleLibrary.shared`) but does not register a log sink, diagnostics controller, or crash reporter at launch.

**`Sources/App/SequencerAIAppDelegate.swift`**

- Lifecycle events log through a small `log(_:)` wrapper that prefixes messages with `[SequencerAIAppDelegate]`.
- Current app-level logging is limited to launch warmup, `applicationDidResignActive`, and `applicationWillTerminate`.
- This gives basic lifecycle breadcrumbs, but there is no severity model, no session ID, no document ID, and no routing to a durable issue store.

**`Sources/Engine/EngineController.swift`**

- The engine has its own `log(_:)` wrapper around `NSLog("[EngineController] ...")`.
- It logs setup failures, shutdown start/complete, some audio-unit preparation paths, route sync details, and coarse apply failures.
- Logging is useful for local debugging, but the messages are plain strings and do not carry structured fields like fingerprint, subsystem code, project/document identity, or build metadata.

**`Sources/Engine/Executor.swift`**

- This is the only inspected runtime path using `OSLog.Logger` rather than `NSLog`.
- The current usage is very small: one debug log when a queued parameter update targets an unknown block.
- There is no shared logging façade, no unified category map, and no signpost or structured-event wrapper for the rest of the app.

**`Sources/UI/StepGridView.swift`**

- `StepGridTapDiagnostics` emits `NSLog` traces only inside `#if DEBUG`.
- The output is helpful for local interaction debugging (`singleTapRecognized`, `cellStateChanged`, mouse-down probes), but it is intentionally ephemeral and debug-only.
- This is not a user-facing observability surface and would disappear from release builds.

**`Sources/UI/TrackDestinationEditor.swift` and `Sources/UI/TrackDestination/PresetBrowserSheetViewModel.swift`**

- UI- and AU-related failures are logged locally with `NSLog`, for example preset stepping failures, AU window preparation timeouts, and preset load failures.
- These logs are not normalized into typed app events, and there is no higher-level issue creation path when they repeat.

### Durable Storage and Persistence

**`Sources/Platform/AppSupportBootstrap.swift` and `wiki/pages/app-support-layout.md`**

- The app owns an Application Support root at `~/Library/.../sequencer-ai/` and creates library subfolders on first launch.
- The wiki explicitly documents that logs are currently `NSLog` only and that there is no per-file log rotation yet.
- No `logs/`, `diagnostics/`, `issues/`, or `observability/` directory exists in the current app-support bootstrap.

**`Sources/Platform/RecentVoicesStore.swift`**

- There is one existing pattern for durable local JSON state outside documents: `voices/history.json` under Application Support.
- The store already does sorted JSON encode/decode, atomic writes through a temp file, and thread-safe access with an `NSLock`.
- That is a useful implementation precedent for a future local issue/fingerprint store, but today it is unrelated to runtime logs and only tracks recently used voices.

**`Sources/Document/SeqAIDocument.swift` and `Sources/App/SequencerDocumentSession.swift`**

- Document persistence is focused on the sequencer project itself. `SeqAIDocument` serializes `Project` as JSON, and `SequencerDocumentSession` flushes live edits back into the document.
- There is no diagnostics payload in the document model, no issue ledger persisted per project, and no current notion of attaching log-derived evidence to a `.seqai` file.

### Current Automation / Issue Surfaces

**`.claude/state/README.md` and `wiki/pages/automation-setup.md`**

- The implementation behaviour tree already has durable markdown queues for `inbox/`, `review-queue/`, `work-item.md`, `candidates.md`, and related state.
- These queues are for automation control and code-review findings, not for app runtime logs.
- The loop can already route a human question, critique, or work item once such a file exists, but nothing in the app writes runtime evidence into this state.

**`scripts/roadmap/next-roadmap-actions.sh`, `scripts/roadmap/commit-roadmap-action.sh`, and `docs/working-through-a-roadmap.md`**

- The roadmap PM loop can turn markdown artifacts under `docs/roadmap/**` into deterministic PM actions.
- This is a planning/work-queue system, not an incident pipeline. It does not ingest application logs or deduplicate repeated failures.

### Build Provenance

**`project.yml`**

- The app bundle currently carries only `CFBundleShortVersionString: "0.0.1"` and `CFBundleVersion: "1"`.
- There is no build-time injection of git SHA, branch, build timestamp, or dirty-tree status into the app bundle or runtime logs.

**`scripts/roadmap/next-roadmap-actions.sh` and `scripts/roadmap/build-dashboard.sh`**

- Repo-side automation can read `git rev-parse --short HEAD`, branch names, and worktree dirty counts.
- That provenance exists in the automation layer only; it is not embedded into emitted app log events, so a log line alone cannot honestly claim "observed in commit X" today.

### User-Facing UI

**`Sources/UI/PreferencesView.swift`**

- Preferences currently has `General`, `MIDI`, and `Audio` tabs only, and both General and Audio are placeholders.
- There is no diagnostics/observability settings panel, no log viewer, no suppression list UI, and no generated-issues review screen.

---

## Where Current Experience Diverges from User Stories

| Story | Gap |
|---|---|
| 1. Collect runtime log evidence | No authoritative collector exists; app logs go to `NSLog`/Console and not to a project-owned pipeline |
| 2. Convert logs into structured events | Most logs are plain strings; there is no typed event schema, parser, or normalized envelope |
| 3. Collapse duplicate events | No fingerprint store, first-seen/last-seen ledger, or occurrence counter exists |
| 4. Separate issues from observations | No thresholding, suppression, or severity policy exists beyond ad-hoc developer judgment |
| 5. Attach honest commit provenance | Bundle has app version/build only; no git SHA/branch/dirty metadata is embedded in the app |
| 6. Route work to the right queue | Automation queues exist, but no bridge writes runtime failures into `.claude/state/` or another issue queue |
| 7. Preserve useful reproduction context | Current logs rarely include document/session/action context; there is no retained evidence artifact |
| 8. Protect private user data | No sanitization/redaction layer exists before log lines become durable artifacts |

---

## Model Gaps vs. UX / Workflow Gaps

### Model gaps (no code exists yet)

- `ObservedAppEvent` or equivalent typed diagnostics payload.
- A parser/collector that can read the chosen authoritative log source and normalize events.
- A fingerprint ledger storing first-seen/last-seen metadata, counts, and issue state.
- A provenance model separating "observed in build/commit" from "introduced by".
- A suppression/routing policy model for benign vs actionable events.
- A durable local issue store under Application Support or another explicit root.
- A bridge from observed issues into `.claude/state/`, `docs/roadmap/`, or an external tracker.
- A privacy-redaction pass before logs become persistent artifacts.

### UX / workflow gaps

- No user-visible diagnostics inbox or generated-issues review UI.
- No preference surface for choosing a log source, enabling collection, or reviewing privacy policy.
- No operator workflow for acknowledging/suppressing known benign events.
- No handoff rule in the automation loops for "this issue belongs to the active worker" vs "send to sweeper/triage".

---

## Architecture Constraints

- The current app emits logs through mixed mechanisms (`NSLog` in most places, `Logger` in one engine path). A future observability feature should unify emission before it tries to infer too much from inconsistent string formats.
- The app is sandboxed (`project.yml` + entitlements). Any file-backed collector or issue store must live in allowed app-owned locations such as Application Support or Caches.
- Per-document runtime state lives in `SequencerDocumentSession`, and each document owns its own `EngineController`. If event context needs document identity, the collector must decide whether to attribute at the session layer, the engine layer, or an app-global aggregator.
- The existing automation queues are markdown-first and human-readable. Bridging log-derived issues into them is plausible, but it requires a deterministic translation step rather than writing raw log spam into `.claude/state/`.
- Current repo-side scripts know git branch/HEAD only when run in a worktree. The app itself does not. Honest commit attribution therefore requires new build metadata injection or a companion collector running with repo access.
- `wiki/pages/app-support-layout.md` explicitly says there is no current per-file log rotation. If the chosen authoritative source becomes an app-owned file, that storage lifecycle must be designed, not assumed.

---

## Relevant Tests and Missing Coverage

### Existing tests that touch nearby surfaces

- `Tests/SequencerAITests/App/SequencerAIAppDelegateTests.swift` and `Tests/SequencerAITests/App/TerminateFlushTests.swift` cover lifecycle behaviour around termination and resign-active.
- `Tests/SequencerAITests/UI/PresetBrowserSheetViewModelTests.swift` covers one UI path that currently logs load failures.
- `Tests/SequencerAITests/Platform/RecentVoicesStoreTests.swift` covers the existing local JSON persistence pattern in Application Support.

### Missing coverage

- No tests assert any runtime logging contract or event schema.
- No tests cover log collection from Console / unified logging / crash reports / app-owned log files.
- No tests cover event fingerprinting, duplicate suppression, or occurrence counting.
- No tests cover provenance capture (bundle version, commit SHA, branch, dirty status).
- No tests cover privacy redaction before persistence.
- No tests cover routing log-derived issues into automation queues or external trackers.
