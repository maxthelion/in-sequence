import Foundation
import XCTest
@testable import SequencerAI

final class DestinationSummaryTests: XCTestCase {
    func test_midi_summary() {
        let project = Project.empty
        let destination = Destination.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)

        let summary = DestinationSummary.make(for: destination, in: project, trackID: project.selectedTrackID)

        XCTAssertEqual(summary.typeLabel, "MIDI")
        XCTAssertEqual(summary.iconName, "pianokeys")
        XCTAssertTrue(summary.detail.contains("SequencerAI Out"))
        XCTAssertTrue(summary.detail.contains("ch 1"))
    }

    func test_midi_transpose_appears_when_nonzero() {
        let project = Project.empty
        let destination = Destination.midi(port: .sequencerAIOut, channel: 3, noteOffset: 7)

        let summary = DestinationSummary.make(for: destination, in: project, trackID: project.selectedTrackID)

        XCTAssertTrue(summary.detail.contains("ch 4"))
        XCTAssertTrue(summary.detail.contains("+7"))
    }

    func test_au_instrument_summary() {
        let project = Project.empty
        let destination = Destination.auInstrument(
            componentID: AudioComponentID(type: "aumu", subtype: "TEST", manufacturer: "CDX ", version: 0),
            stateBlob: nil
        )

        let summary = DestinationSummary.make(for: destination, in: project, trackID: project.selectedTrackID)

        XCTAssertEqual(summary.typeLabel, "AU Instrument")
        XCTAssertEqual(summary.iconName, "waveform")
    }

    func test_sample_summary_with_missing_sample() {
        let project = Project.empty
        let destination = Destination.sample(sampleID: UUID(), settings: .default)

        let summary = DestinationSummary.make(for: destination, in: project, trackID: project.selectedTrackID)

        XCTAssertEqual(summary.typeLabel, "Sampler")
        XCTAssertEqual(summary.iconName, "speaker.wave.2")
        XCTAssertEqual(summary.detail, "Sample not in library")
    }

    func test_internal_sampler_summary() {
        let project = Project.empty
        let destination = Destination.internalSampler(bankID: .sliceDefault, preset: "empty-slice")

        let summary = DestinationSummary.make(for: destination, in: project, trackID: project.selectedTrackID)

        XCTAssertEqual(summary.typeLabel, "Internal Sampler")
        XCTAssertEqual(summary.iconName, "rectangle.stack")
    }

    func test_inherit_group_with_no_group_shows_detached() {
        let project = Project.empty

        let summary = DestinationSummary.make(for: .inheritGroup, in: project, trackID: project.selectedTrackID)

        XCTAssertEqual(summary.typeLabel, "Inherit Group")
        XCTAssertEqual(summary.detail, "Not in a group")
    }

    func test_none_summary_is_empty_marker() {
        let project = Project.empty

        let summary = DestinationSummary.make(for: .none, in: project, trackID: project.selectedTrackID)

        XCTAssertEqual(summary.typeLabel, "")
        XCTAssertEqual(summary.iconName, "")
        XCTAssertEqual(summary.detail, "")
    }
}
