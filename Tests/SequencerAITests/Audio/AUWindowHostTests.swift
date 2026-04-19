import AppKit
import XCTest
@testable import SequencerAI

final class AUWindowHostTests: XCTestCase {
    @MainActor
    func test_open_and_close_tracks_window_and_writes_back_state() {
        let host = AUWindowHost()
        let presenter = StubAudioUnitPresenter()
        var capturedStates: [Data?] = []
        let trackID = UUID()

        host.open(for: trackID, presenter: presenter, title: "Track") { state in
            capturedStates.append(state)
        }

        XCTAssertTrue(host.isOpen(for: trackID))
        XCTAssertEqual(presenter.requestCount, 1)

        host.close(for: trackID)

        XCTAssertFalse(host.isOpen(for: trackID))
        XCTAssertEqual(capturedStates.count, 1)
        XCTAssertEqual(capturedStates[0], presenter.stateData)
    }

    @MainActor
    func test_open_same_key_twice_reuses_existing_window() {
        let host = AUWindowHost()
        let presenter = StubAudioUnitPresenter()
        let trackID = UUID()

        host.open(for: trackID, presenter: presenter, title: "Track") { _ in }
        host.open(for: trackID, presenter: presenter, title: "Track") { _ in }

        XCTAssertTrue(host.isOpen(for: trackID))
        XCTAssertEqual(presenter.requestCount, 1)

        host.close(for: trackID)
    }
}

private final class StubAudioUnitPresenter: AudioUnitWindowPresentable {
    var requestCount = 0
    let stateData = Data([0xAB, 0xCD])

    @MainActor
    func requestHostedViewController(_ completion: @escaping (NSViewController?) -> Void) {
        requestCount += 1
        completion(NSViewController())
    }

    @MainActor
    func captureHostedState() throws -> Data? {
        stateData
    }
}
