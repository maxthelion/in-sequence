import Foundation
import XCTest
@testable import SequencerAI

final class AutosliceAnalysisTests: XCTestCase {
    func test_defaultConfiguration_matchesAcceptedContract() {
        let configuration = AutosliceConfiguration.default

        XCTAssertEqual(configuration.bpmRange, 60...200)
        XCTAssertEqual(configuration.bpmStep, 0.5)
        XCTAssertEqual(configuration.barCounts, [1, 2, 4, 8])
        XCTAssertEqual(configuration.snapToleranceSeconds, 0.030)
        XCTAssertEqual(configuration.maxStartSearchSeconds, 0.500)
        XCTAssertEqual(configuration.shortfallToleranceSeconds, 0.050)
        XCTAssertEqual(configuration.startSearchStepSeconds, 0.005)
        XCTAssertEqual(configuration.candidateDedupSeconds, 0.020)
        XCTAssertEqual(configuration.maxCandidatesPerHypothesis, 3)
        XCTAssertEqual(configuration.maxMergedCandidates, 12)
        XCTAssertFalse(configuration.roleWeightingEnabled)
    }

    func test_cleanFixtures_returnExpectedTopCandidates() throws {
        try assertFixtureTopCandidate("clean-two-bar-120")
        try assertFixtureTopCandidate("clean-one-bar-140")
    }

    func test_tailBleedFixtures_keepTrueLoopRangeHighlyRanked() throws {
        for name in ["two-bar-120-tail-bleed-80ms", "two-bar-120-tail-bleed-200ms"] {
            let fixture = try loadFixture(name)
            let result = AutosliceAnalyzer.analyze(input: fixture.input)
            let expected = fixture.expected

            XCTAssertTrue(
                result.candidates.contains { candidate in
                    abs(candidate.hypothesis.bpm - expected.topBpm) <= 1 &&
                        candidate.hypothesis.bars == expected.topBars &&
                        abs(candidate.startSeconds - expected.topStartSeconds) <= AutosliceConfiguration.default.startSearchStepSeconds &&
                        abs(candidate.endSeconds - expected.topEndSeconds) <= AutosliceConfiguration.default.startSearchStepSeconds &&
                        candidate.compositeScore >= expected.minCompositeScore
                },
                "expected a high-ranked true-duration candidate for \(name), got \(result.candidates.prefix(5))"
            )
        }
    }

    func test_headBleedFixture_prefersNonZeroStart() throws {
        let fixture = try loadFixture("two-bar-120-head-bleed")
        let result = AutosliceAnalyzer.analyze(input: fixture.input)

        let top = try XCTUnwrap(result.candidates.first)
        XCTAssertEqual(top.hypothesis.bars, fixture.expected.topBars)
        XCTAssertEqual(top.hypothesis.bpm, fixture.expected.topBpm, accuracy: 1)
        XCTAssertEqual(top.startSeconds, fixture.expected.topStartSeconds, accuracy: AutosliceConfiguration.default.startSearchStepSeconds)
        XCTAssertGreaterThan(top.startSeconds, 0)
        XCTAssertEqual(top.endSeconds, fixture.expected.topEndSeconds, accuracy: AutosliceConfiguration.default.startSearchStepSeconds)
    }

    func test_ambiguousFixture_returnsCloseDistinctCandidates() throws {
        let fixture = try loadFixture("ambiguous-double-time")
        let result = AutosliceAnalyzer.analyze(input: fixture.input)
        let top = try XCTUnwrap(result.candidates.first)
        let close = result.candidates.dropFirst().filter { candidate in
            candidate.id != top.id && abs(candidate.compositeScore - top.compositeScore) <= 0.10
        }

        XCTAssertFalse(close.isEmpty, "expected at least one close alternate, got \(result.candidates.prefix(5))")
    }

    func test_sparseAndUnknownRoleFixtures_remainAnalyzableWithoutWeighting() throws {
        try assertFixtureTopCandidate("sparse-four-bar-90")
        let unknown = try loadFixture("unknown-roles")
        let result = AutosliceAnalyzer.analyze(input: unknown.input)

        XCTAssertEqual(result.warningKinds, unknown.expected.warnings)
        XCTAssertEqual(result.candidates.first?.hypothesis.bpm ?? 0, unknown.expected.topBpm, accuracy: 1)
        XCTAssertEqual(result.candidates.first?.hypothesis.bars, unknown.expected.topBars)
    }

    func test_roleWeighting_changesRankingOnlyWhenEnabledAndKnownRolesExist() throws {
        let fixture = try loadFixture("role-weighting-ranking")
        var configuration = AutosliceConfiguration.default
        configuration.maxMergedCandidates = 20
        let unweighted = AutosliceAnalyzer.analyze(input: fixture.input, configuration: configuration)

        configuration.roleWeightingEnabled = true
        let weighted = AutosliceAnalyzer.analyze(input: fixture.input, configuration: configuration)

        XCTAssertNotEqual(unweighted.candidates.first?.id, weighted.candidates.first?.id)
        XCTAssertEqual(weighted.candidates.first?.hypothesis.bpm ?? 0, fixture.expected.topBpm, accuracy: 1)
        XCTAssertEqual(weighted.candidates.first?.hypothesis.bars, fixture.expected.topBars)
        XCTAssertEqual(weighted.warningKinds, fixture.expected.warnings)
    }

    func test_roleWeightingWithUnknownRoles_warnsButStillReturnsCandidates() throws {
        let fixture = try loadFixture("unknown-roles")
        var configuration = AutosliceConfiguration.default
        configuration.roleWeightingEnabled = true

        let result = AutosliceAnalyzer.analyze(input: fixture.input, configuration: configuration)

        XCTAssertTrue(result.warningKinds.contains(.roleWeightingWithoutKnownRoles))
        XCTAssertFalse(result.candidates.isEmpty)
    }

    func test_tooShortFixture_warnsInsteadOfReturningFalseExactLoop() throws {
        let fixture = try loadFixture("too-short")
        let result = AutosliceAnalyzer.analyze(input: fixture.input)

        XCTAssertTrue(result.warningKinds.contains(.sampleTooShort) || result.warningKinds.contains(.lowConfidenceTopCandidate))
        if let top = result.candidates.first {
            XCTAssertLessThan(top.compositeScore, 0.99)
        }
    }

    func test_invalidAndOutOfRangeConfiguration_recoversWithWarnings() throws {
        let fixture = try loadFixture("clean-two-bar-120")
        let configuration = AutosliceConfiguration(
            bpmRange: 60...200,
            bpmStep: 0,
            barCounts: [],
            snapToleranceSeconds: Double.nan,
            maxStartSearchSeconds: 1.5,
            shortfallToleranceSeconds: -1,
            startSearchStepSeconds: 0,
            candidateDedupSeconds: -0.1,
            maxCandidatesPerHypothesis: 0,
            maxMergedCandidates: -1,
            roleWeightingEnabled: false
        )

        let result = AutosliceAnalyzer.analyze(input: fixture.input, configuration: configuration)

        XCTAssertTrue(result.warningKinds.contains(.invalidConfigurationRecovered))
        XCTAssertTrue(result.warningKinds.contains(.maxStartSearchClamped))
        XCTAssertFalse(result.candidates.isEmpty)
    }

    func test_repeatedAnalysisIsDeterministicAndCandidateIDIsContentDerived() throws {
        let fixture = try loadFixture("clean-two-bar-120")

        let first = AutosliceAnalyzer.analyze(input: fixture.input)
        let second = AutosliceAnalyzer.analyze(input: fixture.input)

        XCTAssertEqual(first, second)
        let top = try XCTUnwrap(first.candidates.first)
        XCTAssertEqual(top.id, AutosliceCandidateID(bpmTimesTen: 1200, bars: 2, startFrame: 0, endFrame: 176_400))
        XCTAssertEqual(top.id.description, "bpm1200-bars2-start0-end176400")
    }

    private func assertFixtureTopCandidate(_ name: String) throws {
        let fixture = try loadFixture(name)
        let result = AutosliceAnalyzer.analyze(input: fixture.input)
        let top = try XCTUnwrap(result.candidates.first)

        XCTAssertEqual(top.hypothesis.bpm, fixture.expected.topBpm, accuracy: 1, name)
        XCTAssertEqual(top.hypothesis.bars, fixture.expected.topBars, name)
        XCTAssertEqual(top.startSeconds, fixture.expected.topStartSeconds, accuracy: AutosliceConfiguration.default.startSearchStepSeconds, name)
        XCTAssertEqual(top.endSeconds, fixture.expected.topEndSeconds, accuracy: AutosliceConfiguration.default.startSearchStepSeconds, name)
        XCTAssertGreaterThanOrEqual(top.compositeScore, fixture.expected.minCompositeScore, name)
        XCTAssertEqual(result.warningKinds, fixture.expected.warnings, name)
    }

    private func loadFixture(_ name: String) throws -> AutosliceFixture {
        let url = try fixtureURL(named: name)
        let data = try Data(contentsOf: url)
        let fixture = try JSONDecoder().decode(AutosliceFixture.self, from: data)
        XCTAssertEqual(fixture.name, name)
        return fixture
    }

    private func fixtureURL(named name: String) throws -> URL {
        if let bundledURL = Bundle(for: AutosliceAnalysisTests.self)
            .url(forResource: name, withExtension: "json", subdirectory: "Autoslice") {
            return bundledURL
        }

        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: #filePath)
        let candidates = [URL(fileURLWithPath: fileManager.currentDirectoryPath), sourceURL]
        for startURL in candidates {
            var directory = startURL.hasDirectoryPath ? startURL : startURL.deletingLastPathComponent()
            for _ in 0..<8 {
                let fixtureURL = directory
                    .appendingPathComponent("Tests")
                    .appendingPathComponent("Fixtures")
                    .appendingPathComponent("Autoslice")
                    .appendingPathComponent("\(name).json")
                if fileManager.fileExists(atPath: fixtureURL.path) {
                    return fixtureURL
                }
                directory.deleteLastPathComponent()
            }
        }

        throw XCTSkip("missing Autoslice fixture \(name).json")
    }
}

private struct AutosliceFixture: Decodable {
    var name: String
    var sampleRate: Double
    var durationSeconds: Double
    var transients: [Transient]
    var expected: Expected

    var input: AutosliceAnalysisInput {
        AutosliceAnalysisInput(
            durationSeconds: durationSeconds,
            sampleRate: sampleRate,
            frameCount: Int64((durationSeconds * sampleRate).rounded()),
            transients: transients.map { transient in
                AutosliceTransient(
                    frame: Int64((transient.seconds * sampleRate).rounded()),
                    role: transient.role
                )
            }
        )
    }

    struct Transient: Decodable {
        var seconds: Double
        var role: AutosliceTransientRole
    }

    struct Expected: Decodable {
        var topBpm: Double
        var topBars: Int
        var topStartSeconds: Double
        var topEndSeconds: Double
        var minCompositeScore: Double
        var warnings: [AutosliceWarning.Kind]
    }
}

private extension AutosliceResult {
    var warningKinds: [AutosliceWarning.Kind] {
        warnings.map(\.kind)
    }
}
