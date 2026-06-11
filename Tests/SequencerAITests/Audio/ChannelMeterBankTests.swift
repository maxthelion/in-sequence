import AVFoundation
import XCTest
@testable import SequencerAI

final class ChannelMeterBankTests: XCTestCase {
    func test_publisherIdentityIsStablePerChannel() {
        let bank = ChannelMeterBank()
        let trackID = UUID()
        let busID = UUID()

        let trackPublisher = bank.publisher(for: .track(trackID))
        let busPublisher = bank.publisher(for: .bus(busID))
        let sendPublisher = bank.publisher(for: .send(.sendA))

        XCTAssertTrue(trackPublisher === bank.publisher(for: .track(trackID)))
        XCTAssertTrue(busPublisher === bank.publisher(for: .bus(busID)))
        XCTAssertTrue(sendPublisher === bank.publisher(for: .send(.sendA)))
        XCTAssertFalse(trackPublisher === busPublisher)
        XCTAssertFalse(busPublisher === sendPublisher)
    }

    @MainActor
    func test_pumpPublishesRecordedPeaksPerChannel() {
        let bank = ChannelMeterBank()
        let trackID = UUID()
        let loud = bank.publisher(for: .track(trackID))
        let quiet = bank.publisher(for: .send(.sendB))

        loud.recordPeakAmplitudes(left: 1.0, right: 0.5)
        bank.pumpOnceForTesting(now: 10)

        XCTAssertEqual(loud.displayState.leftPeakDBFS, 0, accuracy: 0.01)
        XCTAssertEqual(loud.displayState.rightPeakDBFS, -6.02, accuracy: 0.05)
        XCTAssertEqual(quiet.displayState, .silent)
    }

    @MainActor
    func test_recordSilenceEverywhereDecaysAllChannels() {
        let bank = ChannelMeterBank()
        let publisher = bank.publisher(for: .bus(UUID()))
        publisher.recordPeakAmplitudes(left: 1.0, right: 1.0)
        bank.pumpOnceForTesting(now: 100)
        XCTAssertEqual(publisher.displayState.leftPeakDBFS, 0, accuracy: 0.01)

        bank.recordSilenceEverywhere()
        // Long enough past the release slope to decay below the floor.
        bank.pumpOnceForTesting(now: 110)

        XCTAssertEqual(publisher.displayState.leftPeakDBFS, MasterMeterDisplayState.silenceDBFS)
        XCTAssertEqual(publisher.displayState.rightPeakDBFS, MasterMeterDisplayState.silenceDBFS)
    }

    @MainActor
    func test_publisherSkipsRedundantDisplayStateWrites() {
        // One publisher per strip makes a 60Hz unconditional write a page-
        // wide re-render; verify steady silence publishes no state change.
        let publisher = MasterMeterPublisher()
        publisher.publishPendingToMain(now: 1)
        let before = publisher.displayState

        publisher.publishPendingToMain(now: 2)

        XCTAssertEqual(publisher.displayState, before)
        XCTAssertEqual(publisher.displayState, .silent)
    }
}
