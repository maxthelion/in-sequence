# Send-effect amount change hangs the app (deadlock / render-livelock)

> **STATUS: RESOLVED (2026-06-26).** Triaged on branch `audio-routing-cleanup`.
> The hang is structurally gone — the offending shape (a graph mutation /
> `engine.stop()/start()` driven on the live engine while a lock was held across
> a synchronous main hop) was removed by the routing-cleanup work. See
> **Resolution** at the bottom for the code-path evidence, the fixes that
> resolved it, and the regression test. No product-code change was needed for
> this bug; a session-level regression test was added.

FUNCTIONAL bug (hang, not a crash; no crash report, process stays alive).

## Repro
Play a project, then change a channel's **send-effect amount** in the mixer → the
app hangs (audio + UI freeze).

## Diagnosis (from a live `sample` of the wedged process, see hang-sample.txt)
- **TickClock thread** blocked on the engine `stateLock` inside `prepareTick`.
- **Main thread** wedged in a SwiftUI/AppKit layout cycle (CATransaction commit →
  `layoutSubtreeIfNeeded`, 435/435 samples, never returns to the run loop), reached
  via `ObservationGraphMutation.apply`.
- **Audio render thread** starved (2/435 samples actually rendering).

Mechanism: the send-effect `@Observable` mutation drives a synchronous main-thread
layout storm **while the engine `stateLock` is held**, starving the tick and audio
render. This is the mixer render-livelock class (cf. branches
`fix/mixer-render-livelock`, `fix/device-apply-route-resync`; debt RT-7 "mixer drag
fan-out to O(everything) graph refresh"). Reporter notes this "was thought fixed" —
so it regressed or was only partially fixed.

## Likely fix
Release `stateLock` before the `@Observable` bump that triggers synchronous layout,
and/or debounce the mixer graph fan-out so a send-amount drag doesn't refresh the
whole graph per change. Verify with the timing probe (no slow-tick / starvation on
send-amount change while playing).

## Provenance
Found live during the 2026-06-23 observer-sweep W3.13 timing capture. Confirmed NOT
caused by the observer-sweep branch (send-fx mutation path byte-identical main vs
branch).

## Decision (2026-06-23, user)
Fix now. Likely approach: release stateLock before the @Observable bump that triggers synchronous layout, and/or debounce the mixer graph fan-out. User will verify audio behaviour after (CI can't drive real audio).

## Resolution (2026-06-26 — triage on `audio-routing-cleanup`)

**Verdict: ALREADY FIXED by the routing-cleanup work; no remaining hang on the
native-FX send path.** Triaged the current send-effect-amount code path against
the bug's sampled mechanism; the offending shape no longer exists.

### Current code path for a send-effect-amount change
UI slider (`MixerWorkspaceView.sendInsertBinding(...\.wetDry)` / filter cutoff /
bitcrusher binding setters)
→ `SequencerDocumentSession.updateSendBusInsert` → `mutateSendBus`
(`SequencerDocumentSession+SendBusMutations.swift`)
→ `LiveSequencerStore.mutateSendBus` (plain main-thread `@Observable` write, **no
lock**)
→ `EngineController.apply(sendBus:)` (`EngineControllerMixSync.swift` — **does NOT
take `stateLock`**)
→ `MainAudioGraph.installSendBus` → `installSendBuses`.

`installSendBuses` now:
- acquires `graphLock` **inside** the main closure (`performOnMain`), never
  across the main hop (the documented graphLock rule — a wet/cutoff slider drag
  runs on main, so `performOnMain` takes the `Thread.isMainThread` fast path: no
  cross-thread `DispatchQueue.main.sync` at all);
- takes a **value-only fast path** for amount/parameter changes
  (`needsTopologyChange == false`): it configures the live nodes in place and
  **leaves the engine RUNNING** — no `engine.stop()/start()`, no node
  disconnect, no master-meter-tap bounce.

### Why the original hang is structurally gone
The bug sample showed: TickClock blocked on engine `stateLock` in `prepareTick`,
main wedged in a SwiftUI layout/`ObservationGraphMutation.apply` cycle, render
starved. At filing time (`20436048 feat(send-effects)`), `apply(sendBus:)` only
updated `currentDocumentModel`; send buses reached the graph through the broad
master/bus install path, which did `graphLock.lock()` **then** a `performOnMain`
that ran `engine.stop()/start()` on the live engine — a full-engine restart
under a held lock across a main hop. That is exactly the deadlock/livelock class.
Resolved by the routing-cleanup series:
- `b14f0afe` "R2: send/mixer-bus topology changes without full-engine restart"
  and `5f2e77d2` (wire send-bus legs once) — send-bus changes now rebuild on the
  LIVE engine, no stop/start, with the value-only fast path for amount drags.
- `4f41158e` (#47) "Root-fix the lifecycleLock-vs-tick deadlock class" — locks
  are leaf-only; control paths snapshot under the lock then mutate the engine
  after release; DEBUG guards (`assertNotHoldingLifecycleLockForGraphMutation`,
  the `stateLock`-held-across-main-hop D1 guard) prevent silent regression.

The send-FX-amount path never takes `stateLock`, so the D1 cycle (main parked in
`withStateLock` while the tick waits on `stateLock`) cannot form, and the engine
is never stopped/restarted per gesture, so render is not starved.

### Verification (2026-06-26)
- Build: `xcodebuild -scheme SequencerAI -destination 'platform=macOS' build` —
  BUILD SUCCEEDED.
- Routing-stress rig (`scripts/visual-scenarios/routing-stress.sh`, headless real
  HAL, sample/native-FX, hang watchdog): **GATE PASS** — PASS=53, HANG=0,
  CRASH=0, SILENCE=0, CLICK=0(real), POSTFAIL=0, control_fired=yes. Exercises
  add-FX / send-level / route ops live during playback with no hang. Report:
  `.meta/routing-stress/run-20260626-131625.md`.
- Suites green: MainAudioGraphTests, MasterRenderTests, SamplePlaybackEngineTests,
  EngineControllerMuteTests, SequencerDocumentSessionMasterBusTests (the one
  pre-existing failure in that suite —
  `test_mixerBusPerformanceMutations_doNotExportOrApplyDocumentModel` — is
  unrelated: it predates the mute/solo mutual-exclusivity change `ae862ac9`,
  fails identically on stock HEAD).
- Both lints clean: `realtime-path-lint.sh`, `runtime-ownership-lint.sh` (exit 0).

### Regression test added
`Tests/SequencerAITests/App/SequencerDocumentSessionMasterBusTests.swift` →
`test_sendBusAmountDrag_scopedPath_noStateLockHeldAcrossMainHop`: drives a
wetDry-amount drag (many intermediate value-only changes) through the real
session→engine path with `stateLockHoldViolationHandlerForTesting` armed; asserts
**no D1 `stateLock`-across-main-hop violation**, no full document apply, no full
`exportToProject`, one scoped `apply(sendBus:)` per change. Graph-level coverage
already existed
(`MainAudioGraphTests.test_installSendBus_valueOnlyInsertChangeDoesNotChangeTopologyOrStopEngine`
and `..._inlineAUInstantiationCompletesWithoutDeadlockAndWiresNode`).

### Residual / honest scope
- The rig and the new test cover the **native-FX** send path (filter /
  bitcrusher wetDry+params), the unattended tier. An **AU send-effect** (a real
  AU instance on a send bus) takes the same `installSendBus` value-only path for
  a wetDry drag, and the inline-AU-instantiation no-deadlock case is pinned by a
  unit test — but a real-AU live drag has not been driven here (needs a human
  tier: a real AU + the command channel; cf. the separate AU-host AB-BA fix
  `docs/bugs/20260626-au-host-status-readout-deadlock`). Flag for a human
  real-audio pass with an AU send insert to close the AU case fully.
- No product code was changed for this bug (it was already fixed); only the
  regression test was added.
