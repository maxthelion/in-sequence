import AVFoundation
import XCTest
@testable import SequencerAI

// MARK: - Concurrency churn stress net (wave 2d)
//
// Drives the deadlock-shaped loops from the 2026-06-12 concurrency audit
// (D1–D4 + the sampled send-bus self-deadlock + the laggy-slider shape) in
// tight bounded churn, with three detection layers that FAIL — never hang —
// when a fixed deadlock class regresses:
//
// 1. Contract detectors: TickPathMainSyncGuard.violationHandlerForTesting
//    catches any reintroduced tick-path main-sync (D2), any main-sync while
//    holding stateLock (D1), and any graphLock re-entry / hop-under-graphLock
//    (the send-bus Add-FX self-deadlock class). Deterministic — fires the
//    instant the bad edge is taken, no interleaving luck required.
// 2. Liveness watchdogs: every churn worker runs off the main thread and is
//    awaited with XCTWaiter + timeout. The main thread itself never sync-joins
//    an engine queue, so a worker↔queue wedge surfaces as a failed wait, not
//    a wedged runner (the watchdog style from TickPathMainIsolationTests).
// 3. Bounded-work counters: value-only mix/send churn must not grow
//    sendBusTopologyInstallCountForTesting / reconnectTrackOutputCountForTesting
//    (mixer-latency causes 2/3 — the laggy-slider mechanism).
//
// Two fast smoke loops run in the default gate; the full set is env-gated:
//
//   TEST_RUNNER_SEQUENCERAI_STRESS=1 xcodebuild ... test-without-building \
//     -only-testing:SequencerAITests/ConcurrencyChurnStressTests
//
// (docs/testing/concurrency-lane.md has the full lane instructions.)
final class ConcurrencyChurnStressTests: XCTestCase {

    // MARK: - Plumbing

    private final class LockedBox<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: T

        init(_ value: T) {
            _value = value
        }

        var value: T {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
    }

    private final class ViolationRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _contexts: [String] = []

        var contexts: [String] {
            lock.withLock { _contexts }
        }

        func append(_ context: String) {
            lock.withLock { _contexts.append(context) }
        }
    }

    private var savedSimulateConnection = false
    private var violations = ViolationRecorder()

    override func setUp() {
        super.setUp()
        savedSimulateConnection = MainAudioGraph.simulateAudioInputConnectionForTesting
        violations = ViolationRecorder()
        let recorder = violations
        TickPathMainSyncGuard.violationHandlerForTesting = { context in
            recorder.append(context)
        }
    }

    override func tearDown() {
        TickPathMainSyncGuard.violationHandlerForTesting = nil
        MainAudioGraph.simulateAudioInputConnectionForTesting = savedSimulateConnection
        super.tearDown()
    }

    private var fullStressEnabled: Bool {
        ProcessInfo.processInfo.environment["SEQUENCERAI_STRESS"] == "1"
    }

    private func requireFullStress() throws {
        guard fullStressEnabled else {
            throw XCTSkip(
                "Set TEST_RUNNER_SEQUENCERAI_STRESS=1 to run the full concurrency churn set."
            )
        }
    }

    private struct ChurnWorker {
        let label: String
        let body: () -> Void
    }

    /// Runs every worker on its own queue and waits with a hard timeout.
    /// A deadlock anywhere in the churn shows up as `.timedOut` → a FAILED
    /// test. The main thread only waits here (XCTWaiter spins the run loop,
    /// so fire-and-forget main publishes and performOnMain hops keep
    /// draining); it never sync-joins an engine queue, so the runner itself
    /// cannot wedge.
    private func runWatchdogged(
        _ name: String,
        timeout: TimeInterval,
        workers: [ChurnWorker],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var expectations: [XCTestExpectation] = []
        for worker in workers {
            let workerExpectation = expectation(description: "\(name).\(worker.label)")
            DispatchQueue(label: "stress.\(name).\(worker.label)").async {
                worker.body()
                workerExpectation.fulfill()
            }
            expectations.append(workerExpectation)
        }
        let result = XCTWaiter().wait(for: expectations, timeout: timeout)
        XCTAssertEqual(
            result,
            .completed,
            "\(name): churn workers did not finish within \(timeout)s — a deadlock-shaped " +
            "wedge between engine queues (the watchdog FAILS instead of hanging the runner).",
            file: file,
            line: line
        )
    }

    private func assertNoViolations(
        _ name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            violations.contexts,
            [],
            "\(name): concurrency contract detectors fired — each entry is a reintroduced " +
            "deadlock edge (audit 2026-06-12 classes D1/D2 or the graphLock discipline).",
            file: file,
            line: line
        )
    }

    // MARK: - Fixtures

    private func makeTransportFixture(
        bypassRoutingSync: Bool
    ) -> (controller: EngineController, graph: MainAudioGraph, audioInputTrackID: UUID) {
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
        let graph = MainAudioGraph()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutput: CountingAudioSink(),
            mainAudioGraph: graph,
            sampleEngine: CapturingSampleSink(),
            publishesAudioInputCapture: true
        )
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        controller.audioInputCapturePlanOverrideForTesting = { _, bars in
            AudioInputCapturePlan(sampleRate: 44_100, channelCount: 2, maximumFrameCount: max(1, bars * 4096))
        }
        controller.bypassAudioInputRoutingSyncForTesting = bypassRoutingSync

        var (project, _, _) = makeLiveStoreProject(clipPitch: 60)
        project.appendTrack(trackType: .audioInput)
        let audioInputTrackID = project.selectedTrackID
        controller.apply(documentModel: project)
        return (controller, graph, audioInputTrackID)
    }

    private func makeStereoBuffer(amplitude: Float, frames: Int = 64) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            buffer.floatChannelData![0][frame] = amplitude
            buffer.floatChannelData![1][frame] = amplitude
        }
        return buffer
    }

    // MARK: - Detector positive controls (default gate)
    //
    // The churn tests assert "no violations"; these prove the detectors can
    // fire at all, so those assertions cannot pass vacuously.

    func test_graphLockReentryDetector_fires() {
        let graph = MainAudioGraph()

        graph.simulateGraphLockReentryForTesting()

        XCTAssertEqual(violations.contexts.count, 1, "re-entry detector must report exactly once")
        XCTAssertTrue(
            violations.contexts.first?.contains("graphLock is non-recursive") == true,
            "unexpected violation context: \(violations.contexts)"
        )
    }

    func test_mainSyncGuard_reportsHopWhileHoldingStateLock() {
        let recorder = violations
        let expectation = expectation(description: "guard probe ran off-main")
        // worker.async, not .sync: the guard rightly ignores main-thread
        // calls (inline, not a wait).
        DispatchQueue(label: "stress.guard.stateLock").async {
            TickPathMainSyncGuard.stateLockDepthForCurrentThread += 1
            TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("positive control")
            TickPathMainSyncGuard.stateLockDepthForCurrentThread -= 1
            // Outside the lock the same call must stay silent.
            TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("unlocked control")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)

        XCTAssertEqual(
            recorder.contexts,
            ["positive control while holding stateLock (deadlock class D1)"],
            "the hop helpers' stateLock-hold check must fire exactly for the locked probe"
        )
    }

    // MARK: - Loop 1: start/stop/setBPM churn while ticks process (D2 shape)

    private func runTransportChurn(
        name: String,
        transportCycles: Int,
        armCycles: Int,
        bypassRoutingSync: Bool,
        timeout: TimeInterval
    ) {
        let (controller, _, audioInputTrackID) = makeTransportFixture(bypassRoutingSync: bypassRoutingSync)
        let stateLockRecorder = violations
        controller.stateLockHoldViolationHandlerForTesting = { context in
            stateLockRecorder.append("stateLock hold: \(context)")
        }
        // High BPM → the real TickClock queue stays busy between the churned
        // stop()/setBPM() joins, maximizing the D2 window (main↔tick AB-BA).
        controller.setBPM(480)

        runWatchdogged(name, timeout: timeout, workers: [
            // Production calls transport from main; calling from a worker
            // here is deliberate: the worker plays main's role in the AB-BA
            // (parked in TickClock's queue.sync) WITHOUT being able to wedge
            // the runner. A reintroduced tick→main sync hop is caught by the
            // guard handler instead of by an actual deadlock. No SwiftUI
            // observers are registered, so the off-main @Observable writes
            // in start()/stop() are inert in this process.
            ChurnWorker(label: "transport") {
                for cycle in 0..<transportCycles {
                    controller.start()
                    controller.setBPM(Double(240 + (cycle % 6) * 60))
                    controller.stop()
                }
            },
            ChurnWorker(label: "arm") {
                for cycle in 0..<armCycles {
                    _ = controller.armAudioInput(trackID: audioInputTrackID)
                    if cycle % 3 != 0 {
                        _ = controller.cancelAudioInputArm(trackID: audioInputTrackID)
                    }
                    _ = controller.setAudioInputMonitorMode(
                        trackID: audioInputTrackID,
                        mode: cycle % 2 == 0 ? .loop : .input
                    )
                }
            },
            ChurnWorker(label: "feed") {
                for _ in 0..<armCycles {
                    controller.recordAudioInputBufferForTesting(
                        trackID: audioInputTrackID,
                        buffer: self.makeStereoBuffer(amplitude: 0.4)
                    )
                }
            },
            // The input panel's read pattern: withStateLock reads at meter
            // rate — the main-side half of the D1 interleaving.
            ChurnWorker(label: "read") {
                for _ in 0..<(armCycles * 4) {
                    _ = controller.audioInputRuntime(for: audioInputTrackID)
                    _ = controller.audioInputRuntimeTrackIDs
                }
            },
        ])

        controller.stop()
        assertNoViolations(name)
    }

    func test_smoke_transportChurnWhileTicking_neverSyncHopsToMainAndNeverWedges() {
        runTransportChurn(
            name: "transport-churn-smoke",
            transportCycles: 40,
            armCycles: 60,
            bypassRoutingSync: true,
            timeout: 30
        )
    }

    func test_stress_transportChurnWhileTicking_fullGraphRouting() throws {
        try requireFullStress()
        // bypassRoutingSync=false: the tick path's fire-and-forget graph
        // routing publishes run against the real (never-started) AVAudioEngine
        // topology on main — the full D2 surface.
        runTransportChurn(
            name: "transport-churn-full",
            transportCycles: 300,
            armCycles: 400,
            bypassRoutingSync: false,
            timeout: 120
        )
    }

    // MARK: - Loop 2: record-arm/cancel/complete churn (D1/D4 shape)

    func test_stress_recordArmChurn_capturesCompleteAndNothingHopsUnderStateLock() throws {
        try requireFullStress()
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 4,
            publishesAudioInputCapture: true
        )
        controller.audioInputAvailableChannelCountOverrideForTesting = 2
        controller.audioInputCapturePlanOverrideForTesting = { _, bars in
            AudioInputCapturePlan(sampleRate: 44_100, channelCount: 2, maximumFrameCount: max(1, bars * 4096))
        }
        controller.bypassAudioInputRoutingSyncForTesting = true
        var project = Project.empty
        project.appendTrack(trackType: .audioInput)
        let trackID = project.selectedTrackID
        project.tracks[project.selectedTrackIndex].recordBarLength = 1
        controller.apply(documentModel: project)

        let stateLockRecorder = violations
        controller.stateLockHoldViolationHandlerForTesting = { context in
            stateLockRecorder.append("stateLock hold: \(context)")
        }

        let totalTicks: UInt64 = 4_000
        runWatchdogged("record-arm-churn", timeout: 120, workers: [
            // The tick queue: bar boundary every 4 ticks (stepsPerBar 4) —
            // every boundary is a capture begin/complete opportunity.
            ChurnWorker(label: "ticks") {
                for tickIndex in 0..<totalTicks {
                    controller.processTick(tickIndex: tickIndex, now: TimeInterval(tickIndex) * 0.01)
                }
            },
            ChurnWorker(label: "arm") {
                for cycle in 0..<800 {
                    _ = controller.armAudioInput(trackID: trackID)
                    if cycle % 4 == 0 {
                        _ = controller.cancelAudioInputArm(trackID: trackID)
                    }
                    if cycle % 7 == 0 {
                        _ = controller.markAudioInputLoopPlaceholder(trackID: trackID)
                    }
                    _ = controller.setAudioInputRecordBarLength(trackID: trackID, bars: 1 + (cycle % 2))
                }
            },
            ChurnWorker(label: "feed") {
                for _ in 0..<1_000 {
                    controller.recordAudioInputBufferForTesting(
                        trackID: trackID,
                        buffer: self.makeStereoBuffer(amplitude: 0.5)
                    )
                    controller.drainAudioInputCapturePublicationForTesting()
                }
            },
            ChurnWorker(label: "read") {
                for _ in 0..<4_000 {
                    _ = controller.audioInputRuntime(for: trackID)
                }
            },
        ])

        assertNoViolations("record-arm-churn")

        // The state machine must still work after the churn: a clean
        // arm→record→complete pass from a quiescent state.
        _ = controller.cancelAudioInputArm(trackID: trackID)
        _ = controller.setAudioInputRecordBarLength(trackID: trackID, bars: 1)
        let base = ((totalTicks / 4) + 2) * 4 // beyond churned ticks, on a bar boundary
        XCTAssertTrue(controller.armAudioInput(trackID: trackID, pendingStartTick: base))
        controller.processTick(tickIndex: base, now: TimeInterval(base) * 0.01)
        controller.recordAudioInputBufferForTesting(
            trackID: trackID,
            buffer: makeStereoBuffer(amplitude: 0.6)
        )
        controller.drainAudioInputCapturePublicationForTesting()
        controller.processTick(tickIndex: base + 4, now: TimeInterval(base + 4) * 0.01)
        XCTAssertEqual(
            controller.audioInputRuntime(for: trackID)?.armState,
            .hasLoop,
            "record-arm churn corrupted the capture state machine"
        )
    }

    // MARK: - Loop 3: AU preset readout/load churn while notes dispatch (D3 shape)

    /// Loader that never completes: the host queue gets real traffic
    /// (ensureInstrumentLoadedIfNeeded, mix/destination work) without
    /// attaching a live AU — AVAudioUnitMIDIInstrument lifecycle is unstable
    /// under the xcodebuild test host (see AudioInstrumentHostTests skips).
    private final class StallingAudioUnitLoader: @unchecked Sendable {
        func load(
            _ description: AudioComponentDescription,
            completion: @escaping (AVAudioUnit?, Error?) -> Void
        ) {
            _ = description
            _ = completion // intentionally never called
        }
    }

    func test_stress_presetReadoutChurn_whileNotesDispatch_neverJoinsHostQueue() throws {
        try requireFullStress()
        let host = AudioInstrumentHost(
            instrumentChoices: [.builtInSynth],
            initialInstrument: .builtInSynth,
            audioGraph: MainAudioGraph(),
            autoStartEngine: false,
            instantiateAudioUnit: StallingAudioUnitLoader().load
        )
        host.startIfNeeded()

        // Phase 1 — churn liveness: notes (host queue + per-note main hops)
        // against preset/state readouts (must be snapshot reads, D3 fix).
        let note = NoteEvent(pitch: 60, velocity: 100, length: 1, gate: true, voiceTag: nil)
        runWatchdogged("preset-churn", timeout: 60, workers: [
            ChurnWorker(label: "notes") {
                for _ in 0..<2_000 {
                    host.play(noteEvents: [note], bpm: 480, stepsPerBar: 16)
                }
            },
            ChurnWorker(label: "readouts") {
                for _ in 0..<2_000 {
                    _ = host.presetReadout()
                    _ = try? host.captureStateBlob()
                }
            },
            ChurnWorker(label: "mix") {
                for cycle in 0..<2_000 {
                    var mix = TrackMixSettings.default
                    mix.level = Double(cycle % 10) / 10
                    host.setMix(mix)
                }
            },
        ])
        assertNoViolations("preset-churn")

        // Phase 2 — queue-join probe: park the host queue behind main
        // (shutdown's performOnMain sync hop) and busy-spin main WITHOUT
        // draining its queue. presetReadout/captureStateBlob from a worker
        // must complete in microseconds (snapshot reads). If a regression
        // makes them join the host queue again (the D3 cycle), they park
        // behind the busy-spin for its full duration and blow the elapsed
        // budget — a deterministic FAIL, not a wedge (main always resumes).
        host.shutdown() // host-queue item that sync-hops to the busy main
        let spinSeconds: TimeInterval = 0.4
        let clock = ContinuousClock()
        let worstBox = LockedBox(Duration.zero)
        let probeDone = expectation(description: "preset-churn.probe")
        DispatchQueue(label: "stress.preset-churn.probe").async {
            var worst = Duration.zero
            for _ in 0..<50 {
                let elapsed = clock.measure {
                    _ = host.presetReadout()
                    _ = try? host.captureStateBlob()
                }
                worst = max(worst, elapsed)
            }
            worstBox.value = worst
            probeDone.fulfill()
        }
        // Busy-spin main: the shutdown hop (and anything else) cannot drain.
        let spinDeadline = Date().addingTimeInterval(spinSeconds)
        while Date() < spinDeadline {
            // burn — simulates main blocked the way the D3 hang needs
        }
        wait(for: [probeDone], timeout: 30)

        // A snapshot read takes microseconds; a host-queue join would have
        // parked behind the busy-spin for (most of) its full duration. Half
        // the spin window is an unmissable threshold either way.
        let worst = worstBox.value
        let probeBudget = Duration.milliseconds(Int(spinSeconds * 1_000) / 2)
        XCTAssertLessThan(
            worst,
            probeBudget,
            "preset-churn.probe: a preset/state readout took \(worst) while main was busy — " +
            "it joined the host queue again (the D3 main↔host-queue cycle regressed)"
        )
    }

    // MARK: - Loop 4: send-bus insert add/remove/value churn (graphLock self-deadlock shape)

    func test_stress_sendBusInsertChurn_topologyAndValues() throws {
        try requireFullStress()
        let graph = MainAudioGraph()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutput: CountingAudioSink(),
            mainAudioGraph: graph,
            sampleEngine: CapturingSampleSink()
        )
        let (project, _, _) = makeLiveStoreProject(clipPitch: 60)
        controller.apply(documentModel: project)

        let filterInsert = MasterBusInsert.filter()
        let bitcrusherInsert = MasterBusInsert.bitcrusher()
        let valueInsert = MasterBusInsert.filter()

        // Phase 1 — topology + value churn from workers (the sampled wedge
        // was "+ Add FX" on a send bus: installSendBus under graphLock with
        // an inline re-entry). performOnMain hops drain on the waiter's run
        // loop; the graphLock re-entry detector is armed via setUp.
        runWatchdogged("send-bus-churn", timeout: 120, workers: [
            ChurnWorker(label: "topology") {
                for cycle in 0..<60 {
                    let inserts: [SendBusInsert]
                    switch cycle % 3 {
                    case 0: inserts = []
                    case 1: inserts = [filterInsert]
                    default: inserts = [filterInsert, bitcrusherInsert]
                    }
                    controller.apply(sendBus: SendBusState(id: .sendA, inserts: inserts))
                }
            },
            ChurnWorker(label: "values") {
                for cycle in 0..<400 {
                    var insert = valueInsert
                    insert.wetDry = Double(cycle % 100) / 100
                    controller.apply(sendBus: SendBusState(id: .sendB, inserts: [insert]))
                }
            },
        ])
        assertNoViolations("send-bus-churn")

        // Phase 2 — value-only churn must take the fast path: no engine
        // stop/reinstall/start (the per-mouse-move dropout, mixer-latency
        // cause 3).
        let topologyInstallsBefore = graph.sendBusTopologyInstallCountForTesting
        let valuePhaseDone = expectation(description: "send-bus-churn.value-only")
        DispatchQueue(label: "stress.send-bus-churn.value-only").async {
            for cycle in 0..<200 {
                var insert = valueInsert
                insert.wetDry = Double(cycle % 100) / 100
                controller.apply(sendBus: SendBusState(id: .sendB, inserts: [insert]))
            }
            valuePhaseDone.fulfill()
        }
        XCTAssertEqual(XCTWaiter().wait(for: [valuePhaseDone], timeout: 60), .completed)
        XCTAssertEqual(
            graph.sendBusTopologyInstallCountForTesting,
            topologyInstallsBefore,
            "value-only send churn rebuilt the send-bus topology — the wet/dry fast path regressed"
        )
        assertNoViolations("send-bus-churn.value-only")
    }

    // MARK: - Loop 5: view-model mix/send write churn while ticks run (laggy-slider shape)

    private func runViewModelChurn(name: String, batches: Int, ticksPerWave: UInt64) {
        let graph = MainAudioGraph()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutput: CountingAudioSink(),
            mainAudioGraph: graph,
            sampleEngine: CapturingSampleSink()
        )
        // No audio-input track: the tick path must not read the document
        // (audit R1) — this loop measures the main-side write cost only.
        let (project, trackID, _) = makeLiveStoreProject(clipPitch: 60)
        controller.apply(documentModel: project)

        // One deliberate topology install, then values only.
        controller.apply(sendBus: SendBusState(id: .sendA, inserts: [MasterBusInsert.filter()]))
        let appliedSendBus = controller.sendBusStates[.sendA] ?? SendBusState(id: .sendA)
        let topologyInstallsAfterSetup = graph.sendBusTopologyInstallCountForTesting
        let reconnectsAfterSetup = graph.reconnectTrackOutputCountForTesting

        // Tick driver on its own queue for the whole churn.
        let ticksDone = expectation(description: "\(name).ticks")
        let tickQueue = DispatchQueue(label: "stress.\(name).ticks")
        let totalTicks = ticksPerWave * UInt64(batches)
        tickQueue.async {
            for tickIndex in 0..<totalTicks {
                controller.processTick(tickIndex: tickIndex, now: TimeInterval(tickIndex) * 0.01)
            }
            ticksDone.fulfill()
        }

        // Gesture-rate writes from MAIN (production contract: view models
        // write on main), value-only — sends stay nonzero→nonzero.
        for batch in 0..<batches {
            for step in 0..<24 {
                var mix = TrackMixSettings.default
                mix.level = 0.2 + Double((batch + step) % 8) / 10
                mix.sendA = 0.1 + Double(step % 9) / 10
                controller.setMix(trackID: trackID, mix: mix)

                var sendBus = appliedSendBus
                if !sendBus.inserts.isEmpty {
                    sendBus.inserts[0].wetDry = Double(step % 10) / 10
                }
                controller.apply(sendBus: sendBus)
            }
            // Brief drain so fire-and-forget publishes flow like a real
            // gesture stream.
            RunLoop.current.run(until: Date().addingTimeInterval(0.002))
        }

        let result = XCTWaiter().wait(for: [ticksDone], timeout: 60)
        XCTAssertEqual(result, .completed, "\(name): tick driver wedged during main-side write churn")

        XCTAssertEqual(
            graph.sendBusTopologyInstallCountForTesting,
            topologyInstallsAfterSetup,
            "\(name): value-only mix/send churn triggered send-bus topology rebuilds " +
            "(the laggy-slider mechanism, mixer-latency cause 3)"
        )
        XCTAssertEqual(
            graph.reconnectTrackOutputCountForTesting,
            reconnectsAfterSetup,
            "\(name): value-only mix churn rewired track outputs (mixer-latency cause 2)"
        )
        assertNoViolations(name)
    }

    func test_smoke_viewModelMixSendChurn_staysOnValueFastPaths() {
        runViewModelChurn(name: "view-model-churn-smoke", batches: 8, ticksPerWave: 40)
    }

    func test_stress_viewModelMixSendChurn_full() throws {
        try requireFullStress()
        runViewModelChurn(name: "view-model-churn-full", batches: 120, ticksPerWave: 60)
    }
}
