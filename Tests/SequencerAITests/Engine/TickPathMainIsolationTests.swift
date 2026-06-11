import AVFoundation
import XCTest
@testable import SequencerAI

// MARK: - Tick-path main-isolation watchdog (wave 2a)
//
// The contract (architecture verdict 2026-06-12 §1): nothing on the tick
// path may synchronously wait on main. When it does, main-thread load
// becomes playback load — observed live as the tracks-page BPM sag, and in
// the worst case (main blocked) as a full deadlock.
//
// Two nets here:
//
// 1. A TIMING watchdog: processTick is driven on a dedicated queue while
//    the main thread is deliberately saturated (busy-spin chunks with brief
//    run-loop drains). If anyone reintroduces a tick-path main.sync, each
//    tick parks for most of a busy chunk (~150ms) and the median blows the
//    budget by an order of magnitude. The budget is RELATIVE-first
//    (10× the idle-main baseline median) with a generous absolute floor
//    (20ms ≈ 400× a healthy tick), so CI load cannot fail it the way the
//    wall-clock TickClock interval tests flake — medians over 64 ticks
//    absorb preemption spikes, and no assertion compares against real time
//    deadlines.
//
// 2. The DEBUG marker mechanism (TickPathMainSyncGuard): processTick marks
//    its thread, every sync-to-main helper in Sources/Audio reports before
//    parking. Tests below prove the marker is live during real tick work
//    and that the detector fires (no vacuous green).
final class TickPathMainIsolationTests: XCTestCase {

    private final class DurationsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _durations: [Duration] = []

        var durations: [Duration] {
            lock.withLock { _durations }
        }

        func append(_ duration: Duration) {
            lock.withLock { _durations.append(duration) }
        }
    }

    private final class FlagBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false

        var value: Bool {
            lock.withLock { _value }
        }

        func set() {
            lock.withLock { _value = true }
        }
    }

    private final class ContextsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _contexts: [String] = []

        var contexts: [String] {
            lock.withLock { _contexts }
        }

        func append(_ context: String) {
            lock.withLock { _contexts.append(context) }
        }
    }

    override func tearDown() {
        TickPathMainSyncGuard.violationHandlerForTesting = nil
        super.tearDown()
    }

    private func makeController(sink: CountingAudioSink = CountingAudioSink()) -> EngineController {
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let (project, _, _) = makeLiveStoreProject(clipPitch: 60)
        controller.apply(documentModel: project)
        return controller
    }

    /// Burns main-thread CPU in `chunk`-long spins with brief run-loop
    /// drains between them (so fire-and-forget publishes still flow, like a
    /// real saturated-but-alive main thread), until `done` is set or
    /// `maxDuration` elapses.
    private func saturateMainThread(
        until done: FlagBox,
        chunk: Duration = .milliseconds(150),
        drainSeconds: TimeInterval = 0.005,
        maxDuration: Duration = .seconds(15)
    ) {
        precondition(Thread.isMainThread)
        let clock = ContinuousClock()
        let deadline = clock.now + maxDuration
        while !done.value, clock.now < deadline {
            let chunkEnd = clock.now + chunk
            while clock.now < chunkEnd {
                // Busy-spin: simulates heavy main-thread work (the
                // pre-wave-2a tracks page re-rendering per tick).
            }
            RunLoop.current.run(until: Date().addingTimeInterval(drainSeconds))
        }
    }

    private func median(_ durations: [Duration]) -> Duration {
        precondition(!durations.isEmpty)
        let sorted = durations.sorted()
        return sorted[sorted.count / 2]
    }

    // MARK: - 1. Timing watchdog

    func test_tickProcessing_staysUnderBudget_whileMainThreadIsSaturated() {
        let controller = makeController()
        let tickQueue = DispatchQueue(label: "test.tick-path-watchdog.driver")
        let clock = ContinuousClock()
        let tickCount: UInt64 = 64

        // Hard contract on the exercised paths: no tick-path main-sync at
        // all (the marker mechanism), regardless of timing.
        let violations = ContextsBox()
        TickPathMainSyncGuard.violationHandlerForTesting = { context in
            violations.append(context)
        }
        controller.stateLockHoldViolationHandlerForTesting = { context in
            violations.append("stateLock hold: \(context)")
        }

        // Warm-up (snapshot bootstrap, first prepare) stays out of both
        // measurement phases.
        tickQueue.sync {
            controller.processTick(tickIndex: 0, now: 0)
        }

        // Phase A — baseline: main thread idle (parked in .sync, not busy).
        var baselineDurations: [Duration] = []
        tickQueue.sync {
            for tickIndex in 1...tickCount {
                let elapsed = clock.measure {
                    controller.processTick(tickIndex: tickIndex, now: TimeInterval(tickIndex) * 0.05)
                }
                baselineDurations.append(elapsed)
            }
        }

        // Phase B — main saturated while the tick driver runs concurrently.
        let loadDurations = DurationsBox()
        let ticksDone = FlagBox()
        let expectation = expectation(description: "ticks finished under main load")
        tickQueue.async {
            for tickIndex in (tickCount + 1)...(tickCount * 2) {
                let elapsed = clock.measure {
                    controller.processTick(tickIndex: tickIndex, now: TimeInterval(tickIndex) * 0.05)
                }
                loadDurations.append(elapsed)
            }
            ticksDone.set()
            expectation.fulfill()
        }
        saturateMainThread(until: ticksDone)
        wait(for: [expectation], timeout: 30)

        let baselineMedian = median(baselineDurations)
        let loadMedian = median(loadDurations.durations)
        // Budget: a healthy tick is pure computation (~tens of µs) and must
        // not care that main is busy. 10× the idle baseline median tolerates
        // genuine scheduling pressure on slow/loaded machines; the 20ms
        // absolute floor keeps the relative term meaningful when the
        // baseline is sub-µs. A reintroduced main.sync waits out most of a
        // 150ms busy chunk per tick, pushing the MEDIAN to ~100ms+ — an
        // order of magnitude over budget, so this cannot flake marginally.
        let budget = max(Duration.milliseconds(20), baselineMedian * 10)

        print("[TickPathWatchdog] baseline median=\(baselineMedian), " +
              "loaded median=\(loadMedian), budget=\(budget)")

        XCTAssertLessThanOrEqual(
            loadMedian,
            budget,
            "Median tick processing time under a saturated main thread " +
            "(\(loadMedian)) exceeded the budget (\(budget), baseline median " +
            "\(baselineMedian)). The tick path is waiting on main again — " +
            "tempo now degrades with UI load (architecture verdict §1)."
        )
        XCTAssertEqual(
            violations.contexts, [],
            "Tick-path main-sync detector fired during playback: " +
            "\(violations.contexts). Nothing on the tick path may " +
            "synchronously wait on main."
        )
    }

    /// Positive control for the load harness: a deliberate main.sync from
    /// the driver queue, under the same saturation, must blow the same
    /// budget — proving the watchdog would catch a reintroduced hop.
    func test_loadHarness_wouldCatchAMainSyncHop() {
        let tickQueue = DispatchQueue(label: "test.tick-path-watchdog.control")
        let clock = ContinuousClock()

        let syncDurations = DurationsBox()
        let probesDone = FlagBox()
        let expectation = expectation(description: "main-sync probes finished")
        tickQueue.async {
            for _ in 0..<5 {
                let elapsed = clock.measure {
                    DispatchQueue.main.sync {}
                }
                syncDurations.append(elapsed)
            }
            probesDone.set()
            expectation.fulfill()
        }
        saturateMainThread(until: probesDone)
        wait(for: [expectation], timeout: 30)

        let worstProbe = syncDurations.durations.max() ?? .zero
        print("[TickPathWatchdog] control: worst main.sync under load = \(worstProbe)")
        XCTAssertGreaterThan(
            worstProbe,
            .milliseconds(20),
            "A synchronous main hop under the saturation harness completed in " +
            "\(worstProbe) — under the watchdog budget. The harness lost its " +
            "sensitivity (busy chunks too short or drains too long), so the " +
            "timing watchdog above can no longer catch a reintroduced hop."
        )
    }

    // MARK: - 2. Marker mechanism

    /// Sink that records whether the tick-path marker is set when the
    /// engine dispatches notes to it — proving processTick runs its real
    /// work (including dispatchTick) under the marker.
    private final class MarkerProbeSink: TrackPlaybackSink, @unchecked Sendable {
        let displayName = "MarkerProbe"
        var isAvailable = true
        let availableInstruments = [AudioInstrumentChoice.builtInSynth]
        private(set) var selectedInstrument = AudioInstrumentChoice.builtInSynth
        var currentAudioUnit: AVAudioUnit?

        private let lock = NSLock()
        private var _markerObservations: [Bool] = []

        var markerObservations: [Bool] {
            lock.withLock { _markerObservations }
        }

        func prepareIfNeeded() {}
        func startIfNeeded() {}
        func stop() {}
        func shutdown() {}
        func setMix(_: TrackMixSettings) {}
        func captureStateBlob() throws -> Data? { nil }
        func setDestination(_: Destination) {}
        func selectInstrument(_ choice: AudioInstrumentChoice) {
            selectedInstrument = choice
        }

        func play(noteEvents: [NoteEvent], bpm _: Double, stepsPerBar _: Int) {
            guard !noteEvents.isEmpty else { return }
            lock.withLock {
                _markerObservations.append(TickPathMainSyncGuard.isOnTickPath)
            }
        }
    }

    func test_processTick_runsDispatchUnderTickPathMarker() {
        let sink = MarkerProbeSink()
        let probeController = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let (project, _, _) = makeLiveStoreProject(clipPitch: 60)
        probeController.apply(documentModel: project)

        let tickQueue = DispatchQueue(label: "test.tick-path-watchdog.marker")
        tickQueue.sync {
            XCTAssertFalse(
                TickPathMainSyncGuard.isOnTickPath,
                "Driver thread must start unmarked"
            )
            for tickIndex in 0..<4 {
                probeController.processTick(tickIndex: UInt64(tickIndex), now: TimeInterval(tickIndex) * 0.05)
            }
            XCTAssertFalse(
                TickPathMainSyncGuard.isOnTickPath,
                "Marker must clear when processTick returns"
            )
        }

        XCTAssertFalse(
            sink.markerObservations.isEmpty,
            "Fixture must dispatch notes through the sink — no observations " +
            "means the marker check proved nothing"
        )
        XCTAssertTrue(
            sink.markerObservations.allSatisfy { $0 },
            "Every note dispatch must run under the tick-path marker; an " +
            "unmarked dispatch means the guard cannot see main-sync hops on " +
            "the real tick path"
        )
    }

    /// Positive control: the detector itself fires for a sync-to-main
    /// attempt from a marked thread (so the empty-violations assertion in
    /// the timing test cannot pass vacuously).
    func test_mainSyncGuard_reportsViolation_fromMarkedThread() {
        let violations = ContextsBox()
        TickPathMainSyncGuard.violationHandlerForTesting = { context in
            violations.append(context)
        }

        // worker.async, not .sync: a sync dispatch from main may execute the
        // block ON the main thread (GCD optimization), and the guard rightly
        // ignores main-thread calls (inline, not a wait).
        let worker = DispatchQueue(label: "test.tick-path-watchdog.guard")
        let expectation = expectation(description: "guard probes ran off-main")
        worker.async {
            TickPathMainSyncGuard.withTickPathMarker {
                TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("positive control")
            }
            // Outside the marker the same call must stay silent.
            TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("unmarked control")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)

        XCTAssertEqual(
            violations.contexts, ["positive control"],
            "The guard must report exactly the marked sync attempt: marked " +
            "threads trip it, unmarked threads do not"
        )
    }
}
