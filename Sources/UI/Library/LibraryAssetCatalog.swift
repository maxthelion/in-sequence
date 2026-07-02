import Foundation

/// One browsable category in the global library.
enum LibraryCategory: String, CaseIterable, Identifiable, Equatable, Sendable {
    case breaks
    case recordings
    case drumKits
    case patternTemplates
    case stepOrderMaps
    /// AU instruments discovered on this machine (EngineController's live
    /// component scan) — browsable so a track can be created straight from
    /// one. Not pool-backed: no add-to-project, no audition.
    case auInstruments
    /// The project's generator pool. Project-scoped rather than a global
    /// file-backed asset, but listed here so generators are browsable next to
    /// every other track-creation seed. No pool toggle (already project-native).
    case generators
    case kick, snare, sidestick, clap
    case hatClosed, hatOpen, hatPedal
    case tomLow, tomMid, tomHi
    case ride, crash, cowbell, tambourine, shaker
    case percussion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .breaks: return "Breaks"
        case .recordings: return "Recordings"
        case .drumKits: return "Drum Kits"
        case .patternTemplates: return "Pattern Templates"
        case .stepOrderMaps: return "Step Order Maps"
        case .auInstruments: return "AU Instruments"
        case .generators: return "Generators"
        default: return sampleCategory?.displayName ?? rawValue
        }
    }

    /// The sample-library category this browses, when sample-backed.
    var sampleCategory: AudioSampleCategory? {
        switch self {
        case .drumKits, .patternTemplates, .stepOrderMaps, .auInstruments, .generators:
            return nil
        default:
            return AudioSampleCategory(rawValue: rawValue)
        }
    }
}

/// One global-library entry, flattened to what the Library page renders.
struct LibraryEntryPresentation: Identifiable, Equatable {
    let poolKind: PooledAssetKind
    let assetID: UUID
    let name: String
    /// Compact facts (length / bars / parts) — never prose.
    let facts: String
    /// Resolvable audio file for audition; nil for non-audio assets.
    let auditionURL: URL?

    var id: String { "\(poolKind.rawValue):\(assetID.uuidString)" }
}

/// A pooled reference resolved for display. Missing assets render as marked
/// missing entries — never a crash, never a raw ID on screen.
struct LibraryPoolEntryPresentation: Identifiable, Equatable {
    let ref: PooledAssetRef
    let name: String
    let facts: String
    let isMissing: Bool
    /// Category to reveal when jumping to the global section.
    let revealCategory: LibraryCategory?

    var id: String { ref.id }
}

/// Pure resolution layer between the global libraries / project pool and the
/// Library page. Holds no state; everything is computed from the inputs.
struct LibraryAssetCatalog {
    let sampleLibrary: AudioSampleLibrary
    let drumAssetLibrary: DrumAssetLibrary
    let recordingLibrary: RecordingLibrary

    static let categories: [LibraryCategory] = LibraryCategory.allCases

    // MARK: - Global entries

    func entryCount(in category: LibraryCategory) -> Int {
        entries(in: category).count
    }

    func entries(in category: LibraryCategory) -> [LibraryEntryPresentation] {
        switch category {
        case .recordings:
            return recordingLibrary.recordings
                .sorted { $0.capturedAt > $1.capturedAt }
                .map { recording in
                    LibraryEntryPresentation(
                        poolKind: .sample,
                        assetID: recording.id,
                        name: recording.name,
                        facts: Self.recordingFacts(recording),
                        auditionURL: recordingLibrary.fileURL(for: recording)
                    )
                }
        case .drumKits:
            return drumAssetLibrary.kits.map { kit in
                LibraryEntryPresentation(
                    poolKind: .drumKit,
                    assetID: kit.id,
                    name: kit.name,
                    facts: Self.countFacts(kit.parts.count, unit: "part"),
                    auditionURL: nil
                )
            }
        case .patternTemplates:
            return drumAssetLibrary.templates.map { template in
                LibraryEntryPresentation(
                    poolKind: .patternTemplate,
                    assetID: template.id,
                    name: template.name,
                    facts: Self.countFacts(template.patterns.count, unit: "part"),
                    auditionURL: nil
                )
            }
        case .stepOrderMaps:
            return drumAssetLibrary.userStepOrderMaps.map { map in
                LibraryEntryPresentation(
                    poolKind: .stepOrderMap,
                    assetID: map.id,
                    name: map.name,
                    facts: "\(map.values.count) steps",
                    auditionURL: nil
                )
            }
        case .auInstruments, .generators:
            // Not pool-backed assets: AU instruments come from the live
            // component scan and generators from the project pool, so the
            // Library page renders their rows directly (no PooledAssetKind /
            // audition / missing-asset semantics to resolve here).
            return []
        default:
            guard let sampleCategory = category.sampleCategory else { return [] }
            return sampleLibrary.samples(in: sampleCategory)
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { sample in
                    LibraryEntryPresentation(
                        poolKind: .sample,
                        assetID: sample.id,
                        name: sample.name,
                        facts: Self.sampleFacts(sample),
                        auditionURL: try? sample.fileRef.resolve(libraryRoot: sampleLibrary.libraryRoot)
                    )
                }
        }
    }

    // MARK: - Pool resolution

    func resolve(_ ref: PooledAssetRef) -> LibraryPoolEntryPresentation {
        switch ref.kind {
        case .sample:
            if let recording = recordingLibrary.recording(id: ref.assetID) {
                return LibraryPoolEntryPresentation(
                    ref: ref,
                    name: recording.name,
                    facts: Self.recordingFacts(recording),
                    isMissing: false,
                    revealCategory: .recordings
                )
            }
            if let sample = sampleLibrary.sample(id: ref.assetID) {
                return LibraryPoolEntryPresentation(
                    ref: ref,
                    name: sample.name,
                    facts: Self.sampleFacts(sample),
                    isMissing: false,
                    revealCategory: LibraryCategory(rawValue: sample.category.rawValue)
                )
            }
            return missing(ref, kindLabel: "Sample")
        case .drumKit:
            guard let kit = drumAssetLibrary.kit(id: ref.assetID) else {
                return missing(ref, kindLabel: "Drum kit")
            }
            return LibraryPoolEntryPresentation(
                ref: ref,
                name: kit.name,
                facts: Self.countFacts(kit.parts.count, unit: "part"),
                isMissing: false,
                revealCategory: .drumKits
            )
        case .patternTemplate:
            guard let template = drumAssetLibrary.template(id: ref.assetID) else {
                return missing(ref, kindLabel: "Pattern template")
            }
            return LibraryPoolEntryPresentation(
                ref: ref,
                name: template.name,
                facts: Self.countFacts(template.patterns.count, unit: "part"),
                isMissing: false,
                revealCategory: .patternTemplates
            )
        case .stepOrderMap:
            guard let map = drumAssetLibrary.stepOrderMap(id: ref.assetID) else {
                return missing(ref, kindLabel: "Step order map")
            }
            return LibraryPoolEntryPresentation(
                ref: ref,
                name: map.name,
                facts: "\(map.values.count) steps",
                isMissing: false,
                revealCategory: .stepOrderMaps
            )
        }
    }

    func resolveAll(_ pool: [PooledAssetRef]) -> [LibraryPoolEntryPresentation] {
        pool.map(resolve)
    }

    private func missing(_ ref: PooledAssetRef, kindLabel: String) -> LibraryPoolEntryPresentation {
        // Canon rule 3: raw IDs are never user-facing labels.
        LibraryPoolEntryPresentation(
            ref: ref,
            name: kindLabel,
            facts: "",
            isMissing: true,
            revealCategory: nil
        )
    }

    // MARK: - Facts formatting

    static func sampleFacts(_ sample: AudioSample) -> String {
        guard let lengthSeconds = sample.lengthSeconds else { return "—" }
        return String(format: "%.2fs", lengthSeconds)
    }

    static func recordingFacts(_ recording: RecordingAsset) -> String {
        var parts = ["\(recording.barCount) bar\(recording.barCount == 1 ? "" : "s")"]
        if let lengthSeconds = recording.lengthSeconds {
            parts.append(String(format: "%.2fs", lengthSeconds))
        }
        parts.append("\(Int(recording.bpm.rounded())) BPM")
        return parts.joined(separator: " · ")
    }

    static func countFacts(_ count: Int, unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }
}
