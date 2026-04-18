import AVFoundation
import XCTest
@testable import SequencerAI

final class AudioInstrumentHostTests: XCTestCase {
    func test_stale_async_instrument_completion_is_ignored() {
        let loader = PendingAudioUnitLoader()
        let host = AudioInstrumentHost(
            instrumentChoices: [.builtInSynth, .testInstrument],
            initialInstrument: .builtInSynth,
            instantiateAudioUnit: loader.load
        )

        XCTAssertEqual(loader.pendingCount, 1)
        XCTAssertFalse(host.isAvailable)

        host.selectInstrument(.testInstrument)
        waitForQueueDrain()

        XCTAssertEqual(loader.pendingCount, 2)
        XCTAssertEqual(host.selectedInstrument, .testInstrument)

        loader.complete(at: 0, with: AVAudioUnitSampler())
        waitForQueueDrain()

        XCTAssertFalse(host.isAvailable)

        loader.complete(at: 1, with: AVAudioUnitSampler())
        waitUntil(timeout: 1) { host.isAvailable }

        XCTAssertTrue(host.isAvailable)
        XCTAssertEqual(host.selectedInstrument, .testInstrument)
        XCTAssertEqual(host.displayName, AudioInstrumentChoice.testInstrument.displayName)
    }

    private func waitForQueueDrain() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }

    private func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }
}

private final class PendingAudioUnitLoader {
    private let lock = NSLock()
    private var completions: [(@Sendable (AVAudioUnit?, Error?) -> Void)] = []

    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return completions.count
    }

    func load(
        _ description: AudioComponentDescription,
        completion: @escaping @Sendable (AVAudioUnit?, Error?) -> Void
    ) {
        lock.lock()
        completions.append(completion)
        lock.unlock()
    }

    func complete(at index: Int, with audioUnit: AVAudioUnit) {
        let completion: (@Sendable (AVAudioUnit?, Error?) -> Void)?
        lock.lock()
        if completions.indices.contains(index) {
            completion = completions[index]
        } else {
            completion = nil
        }
        lock.unlock()

        completion?(audioUnit, nil)
    }
}
