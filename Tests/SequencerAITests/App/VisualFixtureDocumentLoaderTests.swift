import XCTest
@testable import SequencerAI

final class VisualFixtureDocumentLoaderTests: XCTestCase {
    func test_mixerMainOutLiveMeterFixture_decodesAsSampleBackedProject() throws {
        let project = try VisualFixtureDocumentLoader.loadProject(at: fixtureURL)

        XCTAssertEqual(project.tracks.count, 1)
        let track = try XCTUnwrap(project.tracks.first)
        XCTAssertEqual(track.name, "Live Meter Kick")
        XCTAssertEqual(track.mix.level, 1)

        guard case let .sample(sampleID, settings) = track.destination else {
            return XCTFail("fixture track must use a sample destination")
        }
        XCTAssertEqual(sampleID, UUID(uuidString: "b63d8dfa-0e54-5919-85fa-263edd52303f"))
        XCTAssertEqual(settings.gain, 12)

        let pattern = project.patternBank(for: track.id).slot(at: 0)
        XCTAssertEqual(pattern.sourceRef.clipID, UUID(uuidString: "55555555-5555-5555-5555-555555555501"))
        XCTAssertEqual(project.clipPool.first?.content.noteGridLengthSteps, 1)
    }

    func test_environmentLoader_resolvesRelativeFixturePath() throws {
        let project = try XCTUnwrap(
            VisualFixtureDocumentLoader.projectFromEnvironment(
                [VisualFixtureDocumentLoader.environmentKey: "docs/roadmap/mixer-main-out/fixtures/mixer-main-out-live-meter.seqai"],
                currentDirectory: repositoryRoot
            )
        )

        XCTAssertEqual(project.selectedTrack.name, "Live Meter Kick")
    }

    func test_transportPhraseNavigationFixture_decodesSeededPhrasesIncludingLongNames() throws {
        let project = try VisualFixtureDocumentLoader.loadProject(at: transportPhraseNavigationFixtureURL)

        XCTAssertEqual(project.tracks.count, 1)
        XCTAssertEqual(project.selectedTrack.name, "Phrase Nav Track")
        XCTAssertEqual(project.phrases.count, 4)
        XCTAssertEqual(project.phrases.first?.name, "Intro Lift")
        XCTAssertEqual(project.phrases.first?.lengthBars, 8)
        XCTAssertTrue(
            project.phrases.contains {
                $0.name == "Verse - Pocket With A Very Long Name For Truncation"
            }
        )
        XCTAssertTrue(
            project.phrases.contains {
                $0.name == "Outro Texture With Extended Label For Crowded Transport Verification"
            }
        )
        XCTAssertEqual(project.selectedPhraseID, UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaa1"))
    }

    private var fixtureURL: URL {
        repositoryRoot
            .appendingPathComponent("docs/roadmap/mixer-main-out/fixtures/mixer-main-out-live-meter.seqai")
    }

    private var transportPhraseNavigationFixtureURL: URL {
        repositoryRoot
            .appendingPathComponent("docs/roadmap/song-mode-phrase-looping/fixtures/transport-phrase-navigation.seqai")
    }

    private var repositoryRoot: URL {
        if let sourceRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            return URL(fileURLWithPath: sourceRoot)
        }

        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
