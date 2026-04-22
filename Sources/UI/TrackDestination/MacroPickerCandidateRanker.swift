import Foundation

// MARK: - AUParameterDescriptor

/// A flat, serializable snapshot of one parameter from an AU's parameterTree.
/// Populated by `AudioInstrumentHost.parameterReadout(for:)` and consumed
/// by `MacroPickerSheet` and `MacroPickerCandidateRanker`.
struct AUParameterDescriptor: Equatable, Hashable, Sendable {
    let address: UInt64
    let identifier: String
    let displayName: String
    let minValue: Double
    let maxValue: Double
    let defaultValue: Double
    /// Human-readable unit string (e.g. "Hz", "dB", "%"), if available.
    let unit: String?
    /// Ancestor group displayNames, outer-first (e.g. ["Filter", "LPF 12"]).
    let group: [String]
    let isWritable: Bool
}

// MARK: - MacroPickerCandidateRanker

/// Ranks AU parameters into "likely candidates" and "rest" for the macro picker.
///
/// A parameter matches if its `displayName` or any element of `group`
/// case-insensitively contains one of the candidate keywords.
/// `displayName` matches rank higher than `group` matches;
/// shorter display names rank higher than longer ones within the same tier;
/// ties broken by stable `displayName` alphabetical order.
enum MacroPickerCandidateRanker {

    // MARK: - Candidate keywords

    static let candidateKeywords: [String] = [
        "cutoff", "resonance", "filter", "drive", "tone",
        "attack", "decay", "sustain", "release", "env",
        "lfo", "rate", "depth", "amount",
        "pitch", "detune", "fine",
        "reverb", "delay", "chorus", "wet", "dry", "mix",
        "macro"
    ]

    // MARK: - Public API

    /// Partition `params` into likely candidates and the remaining parameters.
    ///
    /// - Returns: A tuple `(candidates, rest)` where `candidates` is sorted
    ///   by match priority and `rest` is alphabetical by displayName.
    ///   Together they contain every element of `params` exactly once.
    static func rank(
        _ params: [AUParameterDescriptor]
    ) -> (candidates: [AUParameterDescriptor], rest: [AUParameterDescriptor]) {
        var candidates: [ScoredParam] = []
        var rest: [AUParameterDescriptor] = []

        for param in params {
            if let score = matchScore(for: param) {
                candidates.append(ScoredParam(param: param, score: score))
            } else {
                rest.append(param)
            }
        }

        let sortedCandidates = candidates.sorted { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score < rhs.score // lower is better
            }
            // Within the same tier, shorter display name first.
            if lhs.param.displayName.count != rhs.param.displayName.count {
                return lhs.param.displayName.count < rhs.param.displayName.count
            }
            // Stable alphabetical tie-break.
            return lhs.param.displayName.localizedCaseInsensitiveCompare(rhs.param.displayName) == .orderedAscending
        }

        let sortedRest = rest.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }

        return (sortedCandidates.map(\.param), sortedRest)
    }

    // MARK: - Private

    private struct ScoredParam {
        let param: AUParameterDescriptor
        /// Lower score = higher priority. 0 = displayName match, 1 = group match.
        let score: Int
    }

    /// Returns the match score (0 = displayName, 1 = group), or nil if no match.
    private static func matchScore(for param: AUParameterDescriptor) -> Int? {
        let name = param.displayName.lowercased()
        for keyword in candidateKeywords where name.contains(keyword) {
            return 0 // displayName match — highest priority
        }

        let groups = param.group.map { $0.lowercased() }
        for keyword in candidateKeywords {
            for group in groups where group.contains(keyword) {
                _ = group
                return 1 // group match — lower priority
            }
        }

        return nil
    }
}
