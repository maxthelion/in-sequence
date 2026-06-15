import Foundation
import XCTest
@testable import SequencerAI

final class TrackRoutingPathSummaryTests: XCTestCase {
    private func summary(
        destination: Destination,
        outputTitle: String,
        sendA: Double = 0,
        sendB: Double = 0
    ) -> TrackRoutingPathSummary {
        let project = Project.empty
        let destinationSummary = DestinationSummary.make(
            for: destination,
            in: project,
            trackID: project.selectedTrackID
        )
        let mix = TrackMixSettings(level: 0.8, pan: 0, isMuted: false, sendA: sendA, sendB: sendB)
        return TrackRoutingPathSummary.make(
            destinationSummary: destinationSummary,
            outputTitle: outputTitle,
            mix: mix
        )
    }

    func test_pillSummary_instrumentArrowDestination() {
        let s = summary(
            destination: .sample(sampleID: UUID(), settings: .default),
            outputTitle: "Bus A"
        )
        // Sample-not-in-library detail still drives the instrument label; the
        // pill always reads INSTRUMENT → DEST.
        XCTAssertEqual(s.destinationLabel, "Bus A")
        XCTAssertTrue(s.pillSummary.contains("→ Bus A"))
        XCTAssertTrue(s.pillSummary.hasPrefix(s.instrumentLabel))
    }

    func test_instrumentLabel_usesDetailHeadAndDropsQualifiers() {
        // MIDI detail carries "SequencerAI Out · ch 1" — the head token group
        // is kept so the pill stays one-glance.
        let s = summary(
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            outputTitle: "Master"
        )
        XCTAssertEqual(s.instrumentLabel, "SequencerAI Out")
        XCTAssertEqual(s.pillSummary, "SequencerAI Out → Master")
    }

    func test_unsetDestination_readsNoInstrument() {
        let s = summary(destination: .none, outputTitle: "Master")
        XCTAssertEqual(s.instrumentLabel, "No instrument")
        XCTAssertEqual(s.pillSummary, "No instrument → Master")
    }

    func test_sendsSummary_nilWhenBothClosed() {
        let s = summary(
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            outputTitle: "Master",
            sendA: 0,
            sendB: 0
        )
        XCTAssertFalse(s.hasActiveSend)
        XCTAssertNil(s.sendsSummary)
    }

    func test_sendsSummary_roundsToPercent() {
        let s = summary(
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
            outputTitle: "Bus A",
            sendA: 0.35,
            sendB: 0.20
        )
        XCTAssertTrue(s.hasActiveSend)
        XCTAssertEqual(s.sendsSummary, "sends 35/20")
    }

    func test_sends_clampedIntoRange() {
        let s = summary(
            destination: .none,
            outputTitle: "Master",
            sendA: 1.5,
            sendB: -0.5
        )
        XCTAssertEqual(s.sendA, 1.0, accuracy: 0.0001)
        XCTAssertEqual(s.sendB, 0.0, accuracy: 0.0001)
        XCTAssertEqual(s.sendsSummary, "sends 100/0")
    }
}
