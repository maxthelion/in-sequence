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
        let stubbedResult: [AudioInstrumentChoice]
        private(set) var scanCallCount = 0
        private let scanDelay: TimeInterval

        init(stubbedResult: [AudioInstrumentChoice], scanDelay: TimeInterval = 0) {
            self.stubbedResult = stubbedResult
            self.scanDelay = scanDelay
        }

        override func performScan() -> [AudioInstrumentChoice] {
            scanCallCount += 1
            if scanDelay > 0 {
                Thread.sleep(forTimeInterval: scanDelay)
            }
            return stubbedResult
        }
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
}
