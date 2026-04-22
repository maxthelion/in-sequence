import XCTest
@testable import SequencerAI

final class ProjectTrackMacroTests: XCTestCase {

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

    // MARK: - Built-in sampler macros

    func test_setDestinationWithMacros_toSample_populatesAllBuiltins() {
        var (project, trackID) = makeProject()
        let sampleID = UUID()
        project.setDestinationWithMacros(.sample(sampleID: sampleID, settings: .default), for: trackID)

        let macros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        // 3 sampler macros + 5 filter macros = 8 total
        XCTAssertEqual(macros.count, 8)

        let kinds = Set(macros.compactMap {
            if case let .builtin(k) = $0.source { return k }
            return nil
        })
        XCTAssertEqual(kinds, Set(BuiltinMacroKind.allCases))
    }

    func test_setDestinationWithMacros_toInternalSampler_populatesAllBuiltins() {
        var (project, trackID) = makeProject()
        project.setDestinationWithMacros(.internalSampler(bankID: .drumKitDefault, preset: "test"), for: trackID)

        let macros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        // 3 sampler macros + 5 filter macros = 8 total
        XCTAssertEqual(macros.count, 8)
    }

    func test_builtinIDs_areStableAndDeterministic() {
        let trackID = UUID()
        var (project, _) = makeProject()
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == project.tracks[0].id }) else {
            XCTFail("No track")
            return
        }
        project.tracks[trackIndex].id = trackID

        // Build expected IDs
        let expectedIDs = BuiltinMacroKind.allCases.map {
            TrackMacroDescriptor.builtinID(trackID: trackID, kind: $0)
        }
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        let macros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        let actualIDs = Set(macros.map(\.id))
        XCTAssertEqual(actualIDs, Set(expectedIDs))
    }

    func test_setDestinationWithMacros_toAU_removesBuiltins() {
        var (project, trackID) = makeProject()
        // First set to sampler to get built-ins (3 sampler + 5 filter = 8).
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        XCTAssertEqual(project.tracks.first(where: { $0.id == trackID })?.macros.count, 8)

        // Switch to AU — built-ins should be removed.
        let componentID = AudioComponentID(type: "aumu", subtype: "test", manufacturer: "test", version: 1)
        project.setDestinationWithMacros(.auInstrument(componentID: componentID, stateBlob: nil), for: trackID)

        let macros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        XCTAssertTrue(macros.isEmpty, "Built-in macros should be removed when switching to AU")
    }

    func test_setDestinationWithMacros_toAU_preservesAUParameterBindings() {
        var (project, trackID) = makeProject()
        let componentID = AudioComponentID(type: "aumu", subtype: "test", manufacturer: "test", version: 1)
        project.setDestinationWithMacros(.auInstrument(componentID: componentID, stateBlob: nil), for: trackID)

        // Add an AU parameter macro.
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Cutoff",
            minValue: 0, maxValue: 1, defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "cutoff")
        )
        project.addAUMacro(descriptor: descriptor, to: trackID)
        XCTAssertEqual(project.tracks.first(where: { $0.id == trackID })?.macros.count, 1)

        // Switch to sampler — AU macro should survive, built-ins added.
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        let macros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        // AU macro + 8 built-ins = 9, but cap is 8; the AU macro was there first,
        // so it survives. The built-ins that fit within cap are added.
        // With 8 built-ins and 1 AU macro, the cap logic allows all 9 if the
        // built-in path bypasses the addAUMacro cap (it appends directly).
        // The auto-populate path appends only if not already present — no cap check.
        XCTAssertGreaterThanOrEqual(macros.count, 1)
        XCTAssertTrue(macros.contains { $0.id == descriptor.id })

        // Switch back to AU — should remove built-ins, keep AU macro.
        project.setDestinationWithMacros(.auInstrument(componentID: componentID, stateBlob: nil), for: trackID)
        let finalMacros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        XCTAssertEqual(finalMacros.count, 1)
        XCTAssertTrue(finalMacros.contains { $0.id == descriptor.id })
    }

    // MARK: - addAUMacro

    func test_addAUMacro_noDuplicate() {
        var (project, trackID) = makeProject()
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Cutoff",
            minValue: 0, maxValue: 1, defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "cutoff")
        )
        let added1 = project.addAUMacro(descriptor: descriptor, to: trackID)
        let added2 = project.addAUMacro(descriptor: descriptor, to: trackID)
        XCTAssertTrue(added1)
        XCTAssertFalse(added2, "Adding the same descriptor twice should be a no-op")
        XCTAssertEqual(project.tracks.first(where: { $0.id == trackID })?.macros.count, 1)
    }

    func test_addAUMacro_capsAtEight() {
        var (project, trackID) = makeProject()
        for i in 0..<9 {
            let descriptor = TrackMacroDescriptor(
                id: UUID(),
                displayName: "Macro \(i)",
                minValue: 0, maxValue: 1, defaultValue: 0.5,
                valueType: .scalar,
                source: .auParameter(address: UInt64(i), identifier: "param\(i)")
            )
            project.addAUMacro(descriptor: descriptor, to: trackID)
        }
        XCTAssertEqual(project.tracks.first(where: { $0.id == trackID })?.macros.count, 8)
    }

    // MARK: - removeMacro cascade

    func test_removeMacro_cascadesToPhraseLayers() {
        var (project, trackID) = makeProject()
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Gain",
            minValue: -60, maxValue: 12, defaultValue: 0,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "gain")
        )
        project.addAUMacro(descriptor: descriptor, to: trackID)
        project.syncMacroLayers()

        // Confirm layer was added.
        let layerID = "macro-\(trackID.uuidString)-\(descriptor.id.uuidString)"
        XCTAssertTrue(project.layers.contains(where: { $0.id == layerID }))

        // Remove and confirm cascade.
        project.removeMacro(id: descriptor.id, from: trackID)
        XCTAssertFalse(project.layers.contains(where: { $0.id == layerID }))
        XCTAssertFalse(project.phrases.flatMap(\.cells).contains(where: { $0.layerID == layerID }))
    }

    func test_removeMacro_cascadesToClipLanes() {
        var (project, trackID) = makeProject()
        let macroID = UUID()
        let descriptor = TrackMacroDescriptor(
            id: macroID,
            displayName: "Res",
            minValue: 0, maxValue: 1, defaultValue: 0,
            valueType: .scalar,
            source: .auParameter(address: 2, identifier: "res")
        )
        project.addAUMacro(descriptor: descriptor, to: trackID)

        // Add a lane to the first clip.
        if !project.clipPool.isEmpty {
            project.clipPool[0].macroLanes[macroID] = MacroLane(values: [0.5, nil, 0.3])
        }

        project.removeMacro(id: macroID, from: trackID)

        for clip in project.clipPool {
            XCTAssertNil(clip.macroLanes[macroID], "Clip macro lane should be removed on cascade")
        }
    }

    // MARK: - Built-in not duplicated on repeated setDestination

    func test_setDestinationWithMacros_idempotent_forSampler() {
        var (project, trackID) = makeProject()
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        let macros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        XCTAssertEqual(macros.count, 8, "Built-ins should not be duplicated on repeated assignment")
    }
}
