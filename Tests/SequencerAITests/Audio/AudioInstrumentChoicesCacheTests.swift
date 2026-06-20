import AVFoundation
import XCTest

@testable import SequencerAI

/// Tests for AudioInstrumentChoiceCache.
///
/// Each test constructs its own FakeCache instance so the shared singleton is not touched
/// (and test isolation is preserved).  The shared-singleton behaviour is validated separately
/// in the defaultChoices round-trip tests.
final class AudioInstrumentChoicesCacheTests: XCTestCase {

    // MARK: - Stub subclass

    /// Subclass that replaces the actual AVAudioUnitComponentManager scan with a controlled
    /// stub so tests run fast and deterministically.
    private final class FakeCache: AudioInstrumentChoiceCache {
        private var stubbedResults: [[AudioInstrumentChoice]]
        private let lock = NSLock()
        private let scanDelay: TimeInterval

        init(stubbedResult: [AudioInstrumentChoice], scanDelay: TimeInterval = 0) {
            self.stubbedResults = [stubbedResult]
            self.scanDelay = scanDelay
        }

        init(stubbedResults: [[AudioInstrumentChoice]], scanDelay: TimeInterval = 0) {
            self.stubbedResults = stubbedResults
            self.scanDelay = scanDelay
        }

        override func performScan() -> [AudioInstrumentChoice] {
            if scanDelay > 0 {
                Thread.sleep(forTimeInterval: scanDelay)
            }
            lock.lock()
            defer { lock.unlock() }
            let index = min(scanCallCount, max(0, stubbedResults.count - 1))
            scanCallCount += 1
            return stubbedResults[index]
        }

        private(set) var scanCallCount = 0
    }

    private final class FakeEffectCache: AudioEffectChoiceCache {
        private var stubbedResults: [[AudioEffectChoice]]
        private let lock = NSLock()
        private let scanDelay: TimeInterval

        init(stubbedResults: [[AudioEffectChoice]], scanDelay: TimeInterval = 0) {
            self.stubbedResults = stubbedResults
            self.scanDelay = scanDelay
        }

        override func performScan() -> [AudioEffectChoice] {
            if scanDelay > 0 {
                Thread.sleep(forTimeInterval: scanDelay)
            }
            lock.lock()
            defer { lock.unlock() }
            let index = min(scanCallCount, max(0, stubbedResults.count - 1))
            scanCallCount += 1
            return stubbedResults[index]
        }

        private(set) var scanCallCount = 0
    }

    // MARK: - Single-scan assertion

    func test_cachedChoices_scansOnlyOnce() {
        let cache = FakeCache(stubbedResult: [.builtInSynth])

        _ = cache.cachedChoices
        _ = cache.cachedChoices
        _ = cache.cachedChoices

        XCTAssertEqual(cache.scanCallCount, 1, "Scan must run exactly once regardless of read count")
    }

    // MARK: - Stable result

    func test_cachedChoices_resultIsStable() {
        let cache = FakeCache(stubbedResult: [.builtInSynth])

        let first = cache.cachedChoices
        let second = cache.cachedChoices

        XCTAssertEqual(first, second, "Cached result must be equal across reads")
    }

    // MARK: - Concurrent callers

    func test_cachedChoices_concurrentCallersDoNotDuplicateScan() {
        // Introduce a delay so concurrent callers overlap with the warming state.
        let cache = FakeCache(stubbedResult: [.builtInSynth], scanDelay: 0.05)

        let readerCount = 8
        let group = DispatchGroup()
        var results: [[AudioInstrumentChoice]] = Array(repeating: [], count: readerCount)
        let resultsLock = NSLock()

        // Start the background warm.
        cache.beginWarmingIfNeeded()

        for i in 0..<readerCount {
            group.enter()
            DispatchQueue.global().async {
                let choices = cache.cachedChoices
                resultsLock.lock()
                results[i] = choices
                resultsLock.unlock()
                group.leave()
            }
        }

        group.wait()

        XCTAssertEqual(cache.scanCallCount, 1, "Exactly one scan must run with concurrent readers")
        for (i, result) in results.enumerated() {
            XCTAssertEqual(result, [.builtInSynth], "Reader \(i) should see the stubbed result")
        }
    }

    // MARK: - beginWarmingIfNeeded is idempotent

    func test_beginWarmingIfNeeded_calledMultipleTimes_scansOnce() {
        let cache = FakeCache(stubbedResult: [.builtInSynth])

        cache.beginWarmingIfNeeded()
        cache.beginWarmingIfNeeded()
        cache.beginWarmingIfNeeded()

        // Allow the background task to complete.
        let drained = expectation(description: "warm drained")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { drained.fulfill() }
        wait(for: [drained], timeout: 1)

        _ = cache.cachedChoices
        XCTAssertEqual(cache.scanCallCount, 1, "Multiple beginWarmingIfNeeded calls must not trigger multiple scans")
    }

    // MARK: - Runtime rescan

    func test_rescanChoices_replacesCachedInstrumentChoices() {
        let first = AudioInstrumentChoice.builtInSynth
        let second = AudioInstrumentChoice.testInstrument
        let cache = FakeCache(stubbedResults: [[first], [first, second]])

        XCTAssertEqual(cache.cachedChoices, [first])

        XCTAssertEqual(cache.rescanChoices(), [first, second])
        XCTAssertEqual(cache.cachedChoices, [first, second])
        XCTAssertEqual(cache.scanCallCount, 2, "Rescan must perform exactly one fresh scan")
    }

    func test_beginRescanIfNeeded_keepsPreviousInstrumentChoicesAvailableWhileScanning() {
        let first = AudioInstrumentChoice.builtInSynth
        let second = AudioInstrumentChoice.testInstrument
        let cache = FakeCache(stubbedResults: [[first], [first, second]], scanDelay: 0.05)

        XCTAssertEqual(cache.cachedChoices, [first])
        XCTAssertTrue(cache.beginRescanIfNeeded())
        XCTAssertEqual(cache.currentChoicesIfAvailable, [first])
        XCTAssertFalse(cache.beginRescanIfNeeded(), "Repeated rescan requests during a scan should be cheap no-ops")

        XCTAssertEqual(cache.cachedChoices, [first, second])
        XCTAssertEqual(cache.scanCallCount, 2)
    }

    func test_rescanChoices_replacesCachedEffectChoicesAndPreservesLargeLists() {
        let first = [Self.effectChoice(named: "Alpha", subtype: 1)]
        let rescanned = (0..<24).map { index in
            Self.effectChoice(named: String(format: "Effect %02d", index), subtype: UInt32(index + 10))
        }
        let cache = FakeEffectCache(stubbedResults: [first, rescanned])

        XCTAssertEqual(cache.cachedChoices, first)

        XCTAssertEqual(cache.rescanChoices(), rescanned)
        XCTAssertEqual(cache.cachedChoices.count, 24)
        XCTAssertEqual(cache.cachedChoices.last?.name, "Effect 23")
        XCTAssertEqual(cache.scanCallCount, 2)
    }

    func test_beginRescanIfNeeded_keepsPreviousEffectChoicesAvailableWhileScanning() {
        let first = [Self.effectChoice(named: "Alpha", subtype: 1)]
        let second = first + [Self.effectChoice(named: "Beta", subtype: 2)]
        let cache = FakeEffectCache(stubbedResults: [first, second], scanDelay: 0.05)

        XCTAssertEqual(cache.cachedChoices, first)
        XCTAssertTrue(cache.beginRescanIfNeeded())
        XCTAssertEqual(cache.currentChoicesIfAvailable, first)
        XCTAssertFalse(cache.beginRescanIfNeeded())

        XCTAssertEqual(cache.cachedChoices, second)
        XCTAssertEqual(cache.scanCallCount, 2)
    }

    // MARK: - defaultChoices round-trip (shared singleton)

    func test_defaultChoices_containsBuiltInSynth() {
        // The shared singleton performs a real scan in the test host.
        let choices = AudioInstrumentChoice.defaultChoices
        XCTAssertTrue(choices.contains(.builtInSynth), "builtInSynth must always be present in defaultChoices")
    }

    func test_defaultChoices_secondCallIsInstant() {
        // Prime the cache.
        _ = AudioInstrumentChoice.defaultChoices

        let start = Date()
        _ = AudioInstrumentChoice.defaultChoices
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.001, "Cached read must complete in under 1 ms (got \(elapsed)s)")
    }

    private static func effectChoice(named name: String, subtype: UInt32) -> AudioEffectChoice {
        AudioEffectChoice(
            name: name,
            manufacturerName: "Codex",
            componentType: kAudioUnitType_Effect,
            componentSubType: subtype,
            componentManufacturer: 0x43445820
        )
    }
}
