import AppKit
import XCTest
@testable import SequencerAI

@MainActor
final class AUWindowHostCloseAllTests: XCTestCase {
    func test_closeAll_empties_windows_dictionary() {
        let host = AUWindowHost()
        let presenterA = StubPresenter()
        let presenterB = StubPresenter()
        let keyA = AUWindowHost.WindowKey.track(UUID())
        let keyB = AUWindowHost.WindowKey.track(UUID())
        var writebacks = 0

        host.open(for: keyA, presenter: presenterA, title: "A") { _ in
            writebacks += 1
        }
        host.open(for: keyB, presenter: presenterB, title: "B") { _ in
            writebacks += 1
        }

        XCTAssertTrue(host.isOpen(for: keyA))
        XCTAssertTrue(host.isOpen(for: keyB))

        host.closeAll()

        XCTAssertFalse(host.isOpen(for: keyA))
        XCTAssertFalse(host.isOpen(for: keyB))
        XCTAssertEqual(writebacks, 2)
    }
}

@MainActor
private final class StubPresenter: AudioUnitWindowPresentable {
    func requestHostedViewController(_ completion: @escaping (NSViewController?) -> Void) {
        completion(NSViewController())
    }

    func captureHostedState() throws -> Data? { nil }
}
