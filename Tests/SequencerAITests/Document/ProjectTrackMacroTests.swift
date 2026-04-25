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

    /// AU→sampler: AU macros are dropped when transitioning into sampler kind.
    /// The sampler has exactly 8 built-in slots; preserving AU macros would require
    /// slot indices beyond 7 which the slotIndex clamp can't represent (C2 fix).
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

        // Switch to sampler — AU macro is dropped (Option A: drop to avoid slot collision).
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        let samplerMacros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        // Only 8 built-in macros; AU macro was dropped.
        XCTAssertEqual(samplerMacros.count, 8)
        XCTAssertFalse(samplerMacros.contains { $0.id == descriptor.id },
            "AU macro must be dropped on sampler kind transition to avoid slot collision")

        // No two macros share a slotIndex.
        let slots = samplerMacros.map(\.slotIndex)
        XCTAssertEqual(slots.count, Set(slots).count, "No two macros may share a slotIndex")

        // Switch back to AU — built-ins removed, no AU macros (they were dropped earlier).
        project.setDestinationWithMacros(.auInstrument(componentID: componentID, stateBlob: nil), for: trackID)
        let finalMacros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        XCTAssertTrue(finalMacros.isEmpty,
            "After sampler→AU transition, no macros should remain (AU were dropped on sampler entry)")
    }

    /// Sampler→AU→sampler round-trip: each sampler leg produces exactly 8 built-ins
    /// in unique slots 0-7 with no collisions.
    func test_setDestinationWithMacros_samplerAUSampler_noSlotCollisions() {
        var (project, trackID) = makeProject()
        let componentID = AudioComponentID(type: "aumu", subtype: "test", manufacturer: "test", version: 1)

        // Start at sampler.
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        let firstSamplerMacros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        XCTAssertEqual(firstSamplerMacros.count, 8)
        let firstSlots = firstSamplerMacros.map(\.slotIndex)
        XCTAssertEqual(firstSlots.count, Set(firstSlots).count, "First sampler leg: no slot collisions")
        XCTAssertEqual(Set(firstSlots), Set(0..<8), "First sampler leg: slots 0-7")

        // Transition to AU.
        project.setDestinationWithMacros(.auInstrument(componentID: componentID, stateBlob: nil), for: trackID)

        // Back to sampler.
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)
        let secondSamplerMacros = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        XCTAssertEqual(secondSamplerMacros.count, 8)
        let secondSlots = secondSamplerMacros.map(\.slotIndex)
        XCTAssertEqual(secondSlots.count, Set(secondSlots).count, "Second sampler leg: no slot collisions")
        XCTAssertEqual(Set(secondSlots), Set(0..<8), "Second sampler leg: slots 0-7")
    }

    /// addAUMacro(slotIndex: nil) on a sampler track with 8 built-ins occupying
    /// slots 0-7 must respect the AU macro cap and return false.
    func test_addAUMacro_onSamplerTrack_doesNotCollideWithBuiltins() {
        var (project, trackID) = makeProject()
        // Transition to sampler so slots 0-7 are occupied by built-ins.
        project.setDestinationWithMacros(.sample(sampleID: UUID(), settings: .default), for: trackID)

        let macrosBefore = project.tracks.first(where: { $0.id == trackID })?.macros ?? []
        XCTAssertEqual(macrosBefore.count, 8, "Sampler track must start with 8 built-in macros")

        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Extra",
            minValue: 0, maxValue: 1, defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 99, identifier: "extra")
        )
        // The AU cap (8 AU macros) and all-slot occupancy both prevent adding.
        // Built-ins count against occupied slots so auto-slot also fails.
        let added = project.addAUMacro(descriptor: descriptor, to: trackID, slotIndex: nil)

        let macrosAfter = project.tracks.first(where: { $0.id == trackID })?.macros ?? []

        // Either the add was rejected or — if accepted — no slot collision occurred.
        if added {
            let slots = macrosAfter.map(\.slotIndex)
            XCTAssertEqual(slots.count, Set(slots).count, "No two macros may share a slotIndex after addAUMacro")
            XCTAssertFalse(
                macrosAfter.filter { if case .builtin = $0.source { return true }; return false }
                    .map(\.slotIndex)
                    .contains(macrosAfter.last?.slotIndex ?? -1),
                "New AU macro must not land on a slot occupied by a built-in"
            )
        } else {
            // Correctly rejected.
            XCTAssertEqual(macrosAfter.count, 8, "Rejected add must leave macro count unchanged")
        }
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

    func test_addAUMacro_respectsRequestedSlotIndex() {
        var (project, trackID) = makeProject()
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Cutoff",
            minValue: 0, maxValue: 1, defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "cutoff")
        )

        let added = project.addAUMacro(descriptor: descriptor, to: trackID, slotIndex: 5)

        XCTAssertTrue(added)
        XCTAssertEqual(project.tracks.first(where: { $0.id == trackID })?.macros.first?.slotIndex, 5)
    }

    func test_addAUMacro_rejectsDuplicateParameterAddress() {
        var (project, trackID) = makeProject()
        let first = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Cutoff A",
            minValue: 0, maxValue: 1, defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "cutoff")
        )
        let second = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Cutoff B",
            minValue: 0, maxValue: 1, defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "cutoff")
        )

        XCTAssertTrue(project.addAUMacro(descriptor: first, to: trackID, slotIndex: 0))
        XCTAssertFalse(project.addAUMacro(descriptor: second, to: trackID, slotIndex: 1))
        XCTAssertEqual(project.tracks.first(where: { $0.id == trackID })?.macros.count, 1)
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
