import Foundation

enum AutosliceAnalyzer {
    static func analyze(
        input: AutosliceAnalysisInput,
        configuration: AutosliceConfiguration = .default
    ) -> AutosliceResult {
        let normalization = NormalizedAutosliceConfiguration(configuration)
        let configuration = normalization.configuration
        let durationSeconds = resolvedDurationSeconds(input: input)
        var warnings = normalization.warnings

        if input.transients.isEmpty {
            warnings.append(.noTransients)
        }
        if durationSeconds <= configuration.shortfallToleranceSeconds {
            warnings.append(.sampleTooShort(valueSeconds: durationSeconds))
        }
        if configuration.roleWeightingEnabled,
           !input.transients.isEmpty,
           input.transients.allSatisfy({ $0.role == .unknown })
        {
            warnings.append(.roleWeightingWithoutKnownRoles)
        }

        let hypothesisOutput = makeHypotheses(durationSeconds: durationSeconds, configuration: configuration)
        warnings.append(contentsOf: hypothesisOutput.warnings)
        if hypothesisOutput.hypotheses.isEmpty {
            warnings.append(.noViableHypotheses)
        }

        var candidates: [AutosliceCandidate] = []
        for hypothesis in hypothesisOutput.hypotheses {
            let perHypothesis = makeCandidates(
                input: input,
                durationSeconds: durationSeconds,
                hypothesis: hypothesis,
                configuration: configuration
            )
            candidates.append(contentsOf: deduplicated(perHypothesis, toleranceSeconds: configuration.candidateDedupSeconds)
                .prefix(configuration.maxCandidatesPerHypothesis))
        }

        candidates = Array(candidates.sortedByAutosliceRank().prefix(configuration.maxMergedCandidates))
        if !hypothesisOutput.hypotheses.isEmpty, candidates.isEmpty {
            warnings.append(.noCandidates)
        }
        if let topCandidate = candidates.first {
            if topCandidate.compositeScore < 0.50 {
                warnings.append(.lowConfidenceTopCandidate)
            } else if topCandidate.coverageScore < 1.0 && topCandidate.durationFitScore < 0.95 {
                warnings.append(.sampleTooShort(valueSeconds: durationSeconds))
            }
        }

        return AutosliceResult(
            hypotheses: hypothesisOutput.hypotheses,
            candidates: candidates,
            warnings: warnings.uniqueByKind()
        )
    }
}

struct AutosliceAnalysisInput: Equatable, Sendable {
    var durationSeconds: Double
    var sampleRate: Double
    var frameCount: Int64
    var transients: [AutosliceTransient]
}

struct AutosliceTransient: Equatable, Sendable {
    var frame: Int64
    var role: AutosliceTransientRole
}

enum AutosliceTransientRole: String, Codable, Sendable {
    case kick
    case snare
    case hat
    case unknown
}

struct AutosliceConfiguration: Equatable, Sendable {
    static let `default` = AutosliceConfiguration(
        bpmRange: 60...200,
        bpmStep: 0.5,
        barCounts: [1, 2, 4, 8],
        snapToleranceSeconds: 0.030,
        maxStartSearchSeconds: 0.500,
        shortfallToleranceSeconds: 0.050,
        startSearchStepSeconds: 0.005,
        candidateDedupSeconds: 0.020,
        maxCandidatesPerHypothesis: 3,
        maxMergedCandidates: 12,
        roleWeightingEnabled: false
    )

    var bpmRange: ClosedRange<Double>
    var bpmStep: Double
    var barCounts: [Int]
    var snapToleranceSeconds: Double
    var maxStartSearchSeconds: Double
    var shortfallToleranceSeconds: Double
    var startSearchStepSeconds: Double
    var candidateDedupSeconds: Double
    var maxCandidatesPerHypothesis: Int
    var maxMergedCandidates: Int
    var roleWeightingEnabled: Bool
}

struct AutosliceBPMHypothesis: Equatable, Sendable {
    var bpm: Double
    var bars: Int
    var expectedDurationSeconds: Double
    var durationErrorSeconds: Double
    var durationFitScore: Double
    var integerBPMPrior: Double
}

struct AutosliceCandidateID: Hashable, Sendable, CustomStringConvertible {
    var bpmTimesTen: Int
    var bars: Int
    var startFrame: Int64
    var endFrame: Int64

    var description: String {
        "bpm\(bpmTimesTen)-bars\(bars)-start\(startFrame)-end\(endFrame)"
    }
}

struct AutosliceCandidate: Equatable, Identifiable, Sendable {
    var id: AutosliceCandidateID
    var hypothesis: AutosliceBPMHypothesis
    var startFrame: Int64
    var endFrame: Int64
    var startSeconds: Double
    var endSeconds: Double
    var alignmentScore: Double
    var durationFitScore: Double
    var coverageScore: Double
    var meanGridDistanceSeconds: Double
    var onGridTransientCount: Int
    var relevantTransientCount: Int
    var compositeScore: Double
    var details: [AutosliceTransientAlignment]
}

struct AutosliceTransientAlignment: Equatable, Sendable {
    var transient: AutosliceTransient
    var adjustedSeconds: Double
    var nearestGridStep: Int
    var distanceSeconds: Double
    var isOnGrid: Bool
    var isInCandidateRange: Bool
}

struct AutosliceResult: Equatable, Sendable {
    var hypotheses: [AutosliceBPMHypothesis]
    var candidates: [AutosliceCandidate]
    var warnings: [AutosliceWarning]
}

struct AutosliceWarning: Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case noTransients
        case noViableHypotheses
        case noCandidates
        case maxStartSearchClamped
        case lowConfidenceTopCandidate
        case roleWeightingWithoutKnownRoles
        case invalidConfigurationRecovered
        case sampleTooShort
    }

    var kind: Kind
    var message: String
    var valueSeconds: Double?
}

private struct NormalizedAutosliceConfiguration {
    var configuration: AutosliceConfiguration
    var warnings: [AutosliceWarning]

    init(_ configuration: AutosliceConfiguration) {
        var normalized = configuration
        var warnings: [AutosliceWarning] = []
        let defaults = AutosliceConfiguration.default

        if !configuration.bpmRange.lowerBound.isFinite ||
            !configuration.bpmRange.upperBound.isFinite ||
            configuration.bpmRange.lowerBound <= 0 {
            normalized.bpmRange = defaults.bpmRange
            warnings.append(.invalidConfigurationRecovered)
        }
        Self.recover(&normalized.bpmStep, defaultValue: defaults.bpmStep, warnings: &warnings)
        if configuration.barCounts.isEmpty || configuration.barCounts.contains(where: { $0 <= 0 }) {
            normalized.barCounts = defaults.barCounts
            warnings.append(.invalidConfigurationRecovered)
        }
        Self.recover(&normalized.snapToleranceSeconds, defaultValue: defaults.snapToleranceSeconds, warnings: &warnings)
        Self.recover(&normalized.maxStartSearchSeconds, defaultValue: defaults.maxStartSearchSeconds, warnings: &warnings)
        Self.recover(&normalized.shortfallToleranceSeconds, defaultValue: defaults.shortfallToleranceSeconds, warnings: &warnings)
        Self.recover(&normalized.startSearchStepSeconds, defaultValue: defaults.startSearchStepSeconds, warnings: &warnings)
        Self.recover(&normalized.candidateDedupSeconds, defaultValue: defaults.candidateDedupSeconds, warnings: &warnings)
        Self.recover(&normalized.maxCandidatesPerHypothesis, defaultValue: defaults.maxCandidatesPerHypothesis, warnings: &warnings)
        Self.recover(&normalized.maxMergedCandidates, defaultValue: defaults.maxMergedCandidates, warnings: &warnings)

        if normalized.maxStartSearchSeconds > 1.000 {
            normalized.maxStartSearchSeconds = 1.000
            warnings.append(.maxStartSearchClamped(valueSeconds: configuration.maxStartSearchSeconds))
        }

        self.configuration = normalized
        self.warnings = warnings.uniqueByKind()
    }

    private static func recover(_ value: inout Double, defaultValue: Double, warnings: inout [AutosliceWarning]) {
        if !value.isFinite || value <= 0 {
            value = defaultValue
            warnings.append(.invalidConfigurationRecovered)
        }
    }

    private static func recover(_ value: inout Int, defaultValue: Int, warnings: inout [AutosliceWarning]) {
        if value <= 0 {
            value = defaultValue
            warnings.append(.invalidConfigurationRecovered)
        }
    }
}

private struct HypothesisOutput {
    var hypotheses: [AutosliceBPMHypothesis]
    var warnings: [AutosliceWarning]
}

private func resolvedDurationSeconds(input: AutosliceAnalysisInput) -> Double {
    guard input.durationSeconds.isFinite, input.durationSeconds > 0 else {
        guard input.sampleRate.isFinite, input.sampleRate > 0, input.frameCount > 0 else {
            return 0
        }
        return Double(input.frameCount) / input.sampleRate
    }
    return input.durationSeconds
}

private func makeHypotheses(durationSeconds: Double, configuration: AutosliceConfiguration) -> HypothesisOutput {
    guard durationSeconds > 0 else {
        return HypothesisOutput(hypotheses: [], warnings: [.sampleTooShort(valueSeconds: durationSeconds)])
    }

    var hypotheses: [AutosliceBPMHypothesis] = []
    var rejectedOnlyForShortfall = false
    var bpm = configuration.bpmRange.lowerBound
    while bpm <= configuration.bpmRange.upperBound + 0.000_001 {
        for bars in configuration.barCounts {
            let expectedDurationSeconds = Double(bars) * 4 * (60 / bpm)
            let durationErrorSeconds = durationSeconds - expectedDurationSeconds
            if durationErrorSeconds >= -configuration.shortfallToleranceSeconds,
               durationErrorSeconds <= configuration.maxStartSearchSeconds {
                hypotheses.append(AutosliceBPMHypothesis(
                    bpm: bpm,
                    bars: bars,
                    expectedDurationSeconds: expectedDurationSeconds,
                    durationErrorSeconds: durationErrorSeconds,
                    durationFitScore: durationFitScore(
                        durationErrorSeconds,
                        maxStartSearchSeconds: configuration.maxStartSearchSeconds,
                        shortfallToleranceSeconds: configuration.shortfallToleranceSeconds
                    ),
                    integerBPMPrior: integerBPMPrior(bpm)
                ))
            } else if durationErrorSeconds < -configuration.shortfallToleranceSeconds,
                      durationErrorSeconds >= -max(0.500, configuration.maxStartSearchSeconds) {
                rejectedOnlyForShortfall = true
            }
        }
        bpm += configuration.bpmStep
    }

    return HypothesisOutput(
        hypotheses: hypotheses,
        warnings: rejectedOnlyForShortfall && hypotheses.isEmpty ? [.sampleTooShort(valueSeconds: durationSeconds)] : []
    )
}

private func makeCandidates(
    input: AutosliceAnalysisInput,
    durationSeconds: Double,
    hypothesis: AutosliceBPMHypothesis,
    configuration: AutosliceConfiguration
) -> [AutosliceCandidate] {
    let loopDurationSeconds = hypothesis.expectedDurationSeconds
    let maxStart = min(configuration.maxStartSearchSeconds, max(0, durationSeconds - loopDurationSeconds))
    let sampleRate = max(input.sampleRate, 1)
    var candidates: [AutosliceCandidate] = []
    var stepIndex = 0

    while true {
        let startSeconds = min(Double(stepIndex) * configuration.startSearchStepSeconds, maxStart)
        let endSeconds = startSeconds + loopDurationSeconds
        if endSeconds <= durationSeconds + configuration.shortfallToleranceSeconds {
            candidates.append(makeCandidate(
                input: input,
                durationSeconds: durationSeconds,
                sampleRate: sampleRate,
                hypothesis: hypothesis,
                startSeconds: startSeconds,
                endSeconds: endSeconds,
                configuration: configuration
            ))
        }
        if startSeconds >= maxStart {
            break
        }
        stepIndex += 1
    }

    return candidates.sortedByAutosliceRank()
}

private func makeCandidate(
    input: AutosliceAnalysisInput,
    durationSeconds: Double,
    sampleRate: Double,
    hypothesis: AutosliceBPMHypothesis,
    startSeconds: Double,
    endSeconds: Double,
    configuration: AutosliceConfiguration
) -> AutosliceCandidate {
    let loopDurationSeconds = endSeconds - startSeconds
    let gridStepSeconds = 60 / hypothesis.bpm / 4
    let alignments = input.transients.map { transient in
        let adjustedSeconds = Double(transient.frame) / sampleRate - startSeconds
        let nearestGridStep = Int((adjustedSeconds / gridStepSeconds).rounded())
        let distanceSeconds = abs(adjustedSeconds - Double(nearestGridStep) * gridStepSeconds)
        let isInCandidateRange = adjustedSeconds >= -configuration.snapToleranceSeconds &&
            adjustedSeconds <= loopDurationSeconds + configuration.snapToleranceSeconds
        return AutosliceTransientAlignment(
            transient: transient,
            adjustedSeconds: adjustedSeconds,
            nearestGridStep: nearestGridStep,
            distanceSeconds: distanceSeconds,
            isOnGrid: distanceSeconds <= configuration.snapToleranceSeconds,
            isInCandidateRange: isInCandidateRange
        )
    }

    let relevantAlignments = alignments.filter(\.isInCandidateRange)
    let relevantWeight = relevantAlignments.reduce(0) { total, alignment in
        total + weight(for: alignment.transient.role, configuration: configuration)
    }
    let onGridWeight = relevantAlignments.filter(\.isOnGrid).reduce(0) { total, alignment in
        total + weight(for: alignment.transient.role, configuration: configuration)
    }
    let alignmentScore = relevantWeight > 0 ? onGridWeight / relevantWeight : 0
    let meanGridDistanceSeconds = relevantAlignments.isEmpty
        ? Double.infinity
        : relevantAlignments.reduce(0) { $0 + $1.distanceSeconds } / Double(relevantAlignments.count)
    let coverageScore = Double(relevantAlignments.count) / Double(max(input.transients.count, 1))
    let candidateDurationFitScore = durationFitScore(
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        durationSeconds: durationSeconds,
        shortfallToleranceSeconds: configuration.shortfallToleranceSeconds,
        maxStartSearchSeconds: configuration.maxStartSearchSeconds
    )
    let compositeScore = 0.65 * alignmentScore +
        0.25 * candidateDurationFitScore +
        0.10 * coverageScore
    let startFrame = Int64((startSeconds * sampleRate).rounded())
    let endFrame = Int64((endSeconds * sampleRate).rounded())

    return AutosliceCandidate(
        id: AutosliceCandidateID(
            bpmTimesTen: Int((hypothesis.bpm * 10).rounded()),
            bars: hypothesis.bars,
            startFrame: startFrame,
            endFrame: endFrame
        ),
        hypothesis: hypothesis,
        startFrame: startFrame,
        endFrame: endFrame,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        alignmentScore: alignmentScore,
        durationFitScore: candidateDurationFitScore,
        coverageScore: coverageScore,
        meanGridDistanceSeconds: meanGridDistanceSeconds,
        onGridTransientCount: relevantAlignments.filter(\.isOnGrid).count,
        relevantTransientCount: relevantAlignments.count,
        compositeScore: compositeScore,
        details: alignments
    )
}

private func durationFitScore(
    _ durationErrorSeconds: Double,
    maxStartSearchSeconds: Double,
    shortfallToleranceSeconds: Double
) -> Double {
    if durationErrorSeconds >= 0 {
        return 1 - min(durationErrorSeconds / maxStartSearchSeconds, 1)
    }
    return 1 - min(abs(durationErrorSeconds) / shortfallToleranceSeconds, 1)
}

private func durationFitScore(
    startSeconds: Double,
    endSeconds: Double,
    durationSeconds: Double,
    shortfallToleranceSeconds: Double,
    maxStartSearchSeconds: Double
) -> Double {
    if endSeconds > durationSeconds {
        return 1 - min((endSeconds - durationSeconds) / shortfallToleranceSeconds, 1)
    }

    let headBleedSeconds = max(0, startSeconds)
    let tailBleedSeconds = max(0, durationSeconds - endSeconds)
    let splitBleedSeconds = min(headBleedSeconds, tailBleedSeconds)
    return 1 - min(splitBleedSeconds / maxStartSearchSeconds, 1)
}

private func integerBPMPrior(_ bpm: Double) -> Double {
    let distanceToInteger = abs(bpm - bpm.rounded())
    let integerScore = max(0, 1 - min(distanceToInteger / 0.5, 1))
    let tempoCenterScore = max(0, 1 - min(abs(bpm - 120) / 120, 1))
    return min(1, integerScore * 0.99 + tempoCenterScore * 0.01)
}

private func weight(for role: AutosliceTransientRole, configuration: AutosliceConfiguration) -> Double {
    guard configuration.roleWeightingEnabled else {
        return 1
    }
    switch role {
    case .kick, .snare:
        return 2
    case .hat, .unknown:
        return 1
    }
}

private func deduplicated(_ candidates: [AutosliceCandidate], toleranceSeconds: Double) -> [AutosliceCandidate] {
    var kept: [AutosliceCandidate] = []
    for candidate in candidates.sortedByAutosliceRank() {
        if kept.contains(where: { abs($0.startSeconds - candidate.startSeconds) <= toleranceSeconds }) {
            continue
        }
        kept.append(candidate)
    }
    return kept.sortedByAutosliceRank()
}

private extension Array where Element == AutosliceCandidate {
    func sortedByAutosliceRank() -> [AutosliceCandidate] {
        sorted { lhs, rhs in
            if lhs.compositeScore != rhs.compositeScore {
                return lhs.compositeScore > rhs.compositeScore
            }
            if lhs.alignmentScore != rhs.alignmentScore {
                return lhs.alignmentScore > rhs.alignmentScore
            }
            if lhs.durationFitScore != rhs.durationFitScore {
                return lhs.durationFitScore > rhs.durationFitScore
            }
            if lhs.coverageScore != rhs.coverageScore {
                return lhs.coverageScore > rhs.coverageScore
            }
            if lhs.hypothesis.integerBPMPrior != rhs.hypothesis.integerBPMPrior {
                return lhs.hypothesis.integerBPMPrior > rhs.hypothesis.integerBPMPrior
            }
            if lhs.meanGridDistanceSeconds != rhs.meanGridDistanceSeconds {
                return lhs.meanGridDistanceSeconds < rhs.meanGridDistanceSeconds
            }
            if lhs.startSeconds != rhs.startSeconds {
                return lhs.startSeconds < rhs.startSeconds
            }
            if lhs.hypothesis.bpm != rhs.hypothesis.bpm {
                return lhs.hypothesis.bpm < rhs.hypothesis.bpm
            }
            return lhs.hypothesis.bars < rhs.hypothesis.bars
        }
    }
}

private extension Array where Element == AutosliceWarning {
    func uniqueByKind() -> [AutosliceWarning] {
        var seen: Set<AutosliceWarning.Kind> = []
        var warnings: [AutosliceWarning] = []
        for warning in self where !seen.contains(warning.kind) {
            seen.insert(warning.kind)
            warnings.append(warning)
        }
        return warnings
    }
}

private extension AutosliceWarning {
    static let noTransients = AutosliceWarning(
        kind: .noTransients,
        message: "No transient frames were supplied.",
        valueSeconds: nil
    )

    static let noViableHypotheses = AutosliceWarning(
        kind: .noViableHypotheses,
        message: "No BPM and bar-count hypothesis fits the configured duration window.",
        valueSeconds: nil
    )

    static let noCandidates = AutosliceWarning(
        kind: .noCandidates,
        message: "Viable BPM hypotheses produced no boundary candidates.",
        valueSeconds: nil
    )

    static let lowConfidenceTopCandidate = AutosliceWarning(
        kind: .lowConfidenceTopCandidate,
        message: "The highest-ranked candidate has low confidence.",
        valueSeconds: nil
    )

    static let roleWeightingWithoutKnownRoles = AutosliceWarning(
        kind: .roleWeightingWithoutKnownRoles,
        message: "Role weighting is enabled but all transient roles are unknown.",
        valueSeconds: nil
    )

    static let invalidConfigurationRecovered = AutosliceWarning(
        kind: .invalidConfigurationRecovered,
        message: "Invalid Autoslice configuration values were recovered to safe defaults.",
        valueSeconds: nil
    )

    static func maxStartSearchClamped(valueSeconds: Double) -> AutosliceWarning {
        AutosliceWarning(
            kind: .maxStartSearchClamped,
            message: "Maximum start search was clamped to one second.",
            valueSeconds: valueSeconds
        )
    }

    static func sampleTooShort(valueSeconds: Double) -> AutosliceWarning {
        AutosliceWarning(
            kind: .sampleTooShort,
            message: "The sample is shorter than an otherwise plausible loop hypothesis.",
            valueSeconds: valueSeconds
        )
    }
}
