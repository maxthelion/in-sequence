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

    @MainActor
    func test_open_same_key_with_new_presenter_reuses_window_insteadOfClosingPluginView() {
        let host = AUWindowHost()
        let firstPresenter = StubAudioUnitPresenter()
        let secondPresenter = StubAudioUnitPresenter()
        let trackID = UUID()
        var capturedStates: [Data?] = []

        host.open(for: trackID, presenter: firstPresenter, title: "Track") { state in
            capturedStates.append(state)
        }
        host.open(for: trackID, presenter: secondPresenter, title: "Track") { _ in
            XCTFail("reopening an already-hosted AU window should keep the original state writeback")
        }

        XCTAssertTrue(host.isOpen(for: trackID))
        XCTAssertEqual(firstPresenter.requestCount, 1)
        XCTAssertEqual(secondPresenter.requestCount, 0)
        XCTAssertEqual(capturedStates.count, 0)

        host.close(for: trackID)

        XCTAssertEqual(capturedStates, [firstPresenter.stateData])
    }

    @MainActor
    func test_group_window_key_reuses_existing_window() {
        let host = AUWindowHost()
        let presenter = StubAudioUnitPresenter()
        let groupID = UUID()

        host.open(for: .group(groupID), presenter: presenter, title: "Drums (Shared)") { _ in }
        host.open(for: .group(groupID), presenter: presenter, title: "Drums (Shared)") { _ in }

        XCTAssertTrue(host.isOpen(for: .group(groupID)))
        XCTAssertEqual(presenter.requestCount, 1)

        host.close(for: .group(groupID))
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
