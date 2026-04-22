import XCTest
@testable import SequencerAI

/// Tests that filter macro bindings are auto-populated when a track's destination
/// becomes sampler-shaped, and that binding ids are stable across destination swaps.
final class ProjectTrackSamplerFilterMacrosTests: XCTestCase {

    // MARK: - Helpers

    private func makeProject(destination: Destination = .none) -> (Project, UUID) {
        let track = StepSequenceTrack(
            name: "Test",
            pitches: [60],
            stepPattern: [true],
            destination: destination,
            velocity: 100,
            gateLength: 4
        )
        let project = Project(
            version: 1,
            tracks: [track],
            selectedTrackID: track.id
        )
        return (project, track.id)
    }

    private func filterMacroIDs(trackID: UUID) -> Set<UUID> {
        let filterKinds: [BuiltinMacroKind] = [
            .samplerFilterCutoff, .samplerFilterReso, .samplerFilterDrive,
            .samplerFilterType, .samplerFilterPoles
        ]
        return Set(filterKinds.map { TrackMacroDescriptor.builtinID(trackID: trackID, kind: $0) })
    }

    // MARK: - Filter bindings added with .sample destination

    func test_toSample_addsFiveFilterBindings() {
        var (project, trackID) = makeProject()
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        let macros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []

        let filterKinds = macros.compactMap { binding -> BuiltinMacroKind? in
            guard case let .builtin(k) = binding.source else { return nil }
            switch k {
            case .samplerFilterCutoff, .samplerFilterReso, .samplerFilterDrive,
                 .samplerFilterType, .samplerFilterPoles:
                return k
            default:
                return nil
            }
        }
        XCTAssertEqual(filterKinds.count, 5)
    }

    func test_toInternalSampler_addsFiveFilterBindings() {
        var (project, trackID) = makeProject()
        project.setDestinationWithMacros(.internalSampler(bankID: .drumKitDefault, preset: "test"), for: trackID)
        let macros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        let filterKinds = macros.compactMap { binding -> BuiltinMacroKind? in
            guard case let .builtin(k) = binding.source else { return nil }
            switch k {
            case .samplerFilterCutoff, .samplerFilterReso, .samplerFilterDrive,
                 .samplerFilterType, .samplerFilterPoles:
                return k
            default:
                return nil
            }
        }
        XCTAssertEqual(filterKinds.count, 5)
    }

    // MARK: - Filter bindings removed on non-sampler destination

    func test_toAUInstrument_removesAllFilterBindings() {
        var (project, trackID) = makeProject()
        // Populate filter bindings.
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        XCTAssertEqual(project.tracks.first(where: { $0.id == trackID })?.macros.count, 8)

        // Switch to AU — all built-ins should be removed.
        let componentID = AudioComponentID(type: "aumu", subtype: "test", manufacturer: "test", version: 1)
        project.setDestinationWithMacros(.auInstrument(componentID: componentID, stateBlob: nil), for: trackID)

        let macros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        XCTAssertTrue(macros.isEmpty)
    }

    // MARK: - Binding id stability across sample/internalSampler swaps

    func test_filterBindingIDs_stableAcrossSampleInternalSamplerSwap() {
        var (project, trackID) = makeProject()

        // Set to .sample and capture IDs.
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        let idsAfterSample = Set(project.tracks.first(where: { $0.id == trackID })?.macros.map(\.id) ?? [])

        // Switch to .internalSampler — IDs must be identical.
        project.setDestinationWithMacros(.internalSampler(bankID: .drumKitDefault, preset: "test"), for: trackID)
        let idsAfterInternal = Set(project.tracks.first(where: { $0.id == trackID })?.macros.map(\.id) ?? [])

        XCTAssertEqual(idsAfterSample, idsAfterInternal,
            "Macro binding IDs must be identical across .sample ↔ .internalSampler swaps")
    }

    func test_filterBindingIDs_notDuplicatedOnRepeatAssignment() {
        var (project, trackID) = makeProject()
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        project.setDestinationWithMacros(.internalSampler(bankID: .drumKitDefault, preset: "p"), for: trackID)
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)

        let macros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        XCTAssertEqual(macros.count, 8, "8 unique built-ins — no duplicates from repeated swaps")
    }

    // MARK: - Clip macro lane survives destination swap

    func test_clipMacroLane_survivesDestinationSwap() {
        var (project, trackID) = makeProject()
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        _ = project.ensureClipForCurrentPattern(trackID: trackID)

        // Get the cutoff binding id.
        let cutoffID = TrackMacroDescriptor.builtinID(trackID: trackID, kind: .samplerFilterCutoff)

        // Write a macro lane on the first clip keyed to the cutoff binding.
        guard !project.clipPool.isEmpty else {
            XCTFail("No clips in pool")
            return
        }
        project.clipPool[0].macroLanes[cutoffID] = MacroLane(values: [0.5, nil, 0.9])

        // Swap to .internalSampler — the binding id is the same, lane must survive.
        project.setDestinationWithMacros(.internalSampler(bankID: .drumKitDefault, preset: "p"), for: trackID)

        XCTAssertNotNil(project.clipPool[0].macroLanes[cutoffID],
            "Clip macro lane keyed to filter cutoff binding should survive .sample → .internalSampler swap")
    }

    // MARK: - Filter descriptor properties

    func test_filterCutoffDescriptor_hasCorrectRange() {
        let trackID = UUID()
        let desc = TrackMacroDescriptor.builtin(trackID: trackID, kind: .samplerFilterCutoff)
        XCTAssertEqual(desc.minValue, 20, accuracy: 0.001)
        XCTAssertEqual(desc.maxValue, 20_000, accuracy: 0.001)
        XCTAssertEqual(desc.defaultValue, 20_000, accuracy: 0.001)
        XCTAssertEqual(desc.valueType, .scalar)
    }

    func test_filterTypeDescriptor_hasPatternIndexType() {
        let trackID = UUID()
        let desc = TrackMacroDescriptor.builtin(trackID: trackID, kind: .samplerFilterType)
        XCTAssertEqual(desc.valueType, .patternIndex)
        XCTAssertEqual(desc.minValue, 0, accuracy: 0.001)
        XCTAssertEqual(desc.maxValue, 3, accuracy: 0.001)
    }

    func test_filterPolesDescriptor_hasPatternIndexType() {
        let trackID = UUID()
        let desc = TrackMacroDescriptor.builtin(trackID: trackID, kind: .samplerFilterPoles)
        XCTAssertEqual(desc.valueType, .patternIndex)
        XCTAssertEqual(desc.minValue, 0, accuracy: 0.001)
        XCTAssertEqual(desc.maxValue, 2, accuracy: 0.001)
        XCTAssertEqual(desc.defaultValue, 1, accuracy: 0.001)  // default = .two
    }
}
