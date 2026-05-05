import Foundation
import XCTest
@testable import SequencerAI

final class ProjectSelectedSlotSourceHelpersTests: XCTestCase {
    private let slotIndex = 3
    private let siblingSlotIndex = 4

    private func makeProject() throws -> (
        project: Project,
        trackID: UUID,
        sourceGeneratorID: UUID,
        modifierGeneratorID: UUID,
        alternateClipID: UUID,
        siblingBaseline: SourceRef
    ) {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let trackID = project.selectedTrack.id
        let originalGenerator = try XCTUnwrap(project.attachNewGenerator(to: trackID))
        let selectedSlotGenerator = try XCTUnwrap(project.attachNewGenerator(to: trackID))
        project.setPatternModifierGeneratorID(originalGenerator.id, bypassed: true, for: trackID, slotIndex: slotIndex)

        let alternateClip = ClipPoolEntry(
            id: UUID(),
            name: "Alternate Clip",
            trackType: .monoMelodic,
            content: .emptyNoteGrid(lengthSteps: 16)
        )
        project.clipPool.append(alternateClip)

        let siblingBaseline = project.patternBank(for: trackID).slot(at: siblingSlotIndex).sourceRef
        return (project, trackID, selectedSlotGenerator.id, originalGenerator.id, alternateClip.id, siblingBaseline)
    }

    func test_removeSelectedSlotSource_leaves_explicit_empty_state_without_creating_replacement_clip() throws {
        var (project, trackID, sourceGeneratorID, modifierGeneratorID, _, siblingBaseline) = try makeProject()
        project.assignGeneratorSource(sourceGeneratorID, to: trackID, slotIndex: slotIndex)
        let baselineClipCount = project.clipPool.count

        project.removeSelectedSlotSource(trackID: trackID, slotIndex: slotIndex)

        let slot = project.patternBank(for: trackID).slot(at: slotIndex)
        XCTAssertEqual(slot.sourceRef.mode, .clip)
        XCTAssertNil(slot.sourceRef.clipID)
        XCTAssertEqual(slot.sourceRef.generatorID, sourceGeneratorID)
        XCTAssertEqual(slot.sourceRef.modifierGeneratorID, modifierGeneratorID)
        XCTAssertTrue(slot.sourceRef.modifierBypassed)
        XCTAssertEqual(project.clipPool.count, baselineClipCount)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: siblingSlotIndex).sourceRef, siblingBaseline)
    }

    func test_createBlankClipSource_updates_only_selected_slot_and_preserves_modifier_state() throws {
        var (project, trackID, sourceGeneratorID, modifierGeneratorID, _, siblingBaseline) = try makeProject()
        let baselineClipCount = project.clipPool.count

        let clipID = try XCTUnwrap(project.createBlankClipSource(trackID: trackID, slotIndex: slotIndex))

        let slot = project.patternBank(for: trackID).slot(at: slotIndex)
        XCTAssertEqual(project.clipPool.count, baselineClipCount + 1)
        XCTAssertEqual(slot.sourceRef.mode, .clip)
        XCTAssertEqual(slot.sourceRef.clipID, clipID)
        XCTAssertEqual(slot.sourceRef.generatorID, sourceGeneratorID)
        XCTAssertEqual(slot.sourceRef.modifierGeneratorID, modifierGeneratorID)
        XCTAssertTrue(slot.sourceRef.modifierBypassed)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: siblingSlotIndex).sourceRef, siblingBaseline)
    }

    func test_assignClipSource_updates_only_selected_slot_and_preserves_modifier_state() throws {
        var (project, trackID, sourceGeneratorID, modifierGeneratorID, alternateClipID, siblingBaseline) = try makeProject()

        project.assignClipSource(alternateClipID, to: trackID, slotIndex: slotIndex)

        let slot = project.patternBank(for: trackID).slot(at: slotIndex)
        XCTAssertEqual(slot.sourceRef.mode, .clip)
        XCTAssertEqual(slot.sourceRef.clipID, alternateClipID)
        XCTAssertEqual(slot.sourceRef.generatorID, sourceGeneratorID)
        XCTAssertEqual(slot.sourceRef.modifierGeneratorID, modifierGeneratorID)
        XCTAssertTrue(slot.sourceRef.modifierBypassed)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: siblingSlotIndex).sourceRef, siblingBaseline)
    }

    func test_createBlankGeneratorSource_updates_only_selected_slot_and_preserves_modifier_state() throws {
        var (project, trackID, _, modifierGeneratorID, _, siblingBaseline) = try makeProject()
        let baselineGeneratorCount = project.generatorPool.count

        let generator = try XCTUnwrap(project.createBlankGeneratorSource(trackID: trackID, slotIndex: slotIndex))

        let slot = project.patternBank(for: trackID).slot(at: slotIndex)
        XCTAssertEqual(project.generatorPool.count, baselineGeneratorCount + 1)
        XCTAssertEqual(slot.sourceRef.mode, .generator)
        XCTAssertEqual(slot.sourceRef.generatorID, generator.id)
        XCTAssertEqual(slot.sourceRef.modifierGeneratorID, modifierGeneratorID)
        XCTAssertTrue(slot.sourceRef.modifierBypassed)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: siblingSlotIndex).sourceRef, siblingBaseline)
    }

    func test_assignGeneratorSource_updates_only_selected_slot_and_preserves_modifier_state() throws {
        var (project, trackID, sourceGeneratorID, modifierGeneratorID, _, siblingBaseline) = try makeProject()

        project.assignGeneratorSource(sourceGeneratorID, to: trackID, slotIndex: slotIndex)

        let slot = project.patternBank(for: trackID).slot(at: slotIndex)
        XCTAssertEqual(slot.sourceRef.mode, .generator)
        XCTAssertEqual(slot.sourceRef.generatorID, sourceGeneratorID)
        XCTAssertEqual(slot.sourceRef.modifierGeneratorID, modifierGeneratorID)
        XCTAssertTrue(slot.sourceRef.modifierBypassed)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: siblingSlotIndex).sourceRef, siblingBaseline)
    }

    func test_createBlankModifierGenerator_updates_only_selected_slot_without_creating_source_material() throws {
        var (project, trackID, sourceGeneratorID, _, _, siblingBaseline) = try makeProject()
        let baselineGeneratorCount = project.generatorPool.count
        let baselineClipCount = project.clipPool.count
        project.removeSelectedSlotSource(trackID: trackID, slotIndex: slotIndex)

        let modifier = try XCTUnwrap(project.createBlankModifierGenerator(trackID: trackID, slotIndex: slotIndex))

        let slot = project.patternBank(for: trackID).slot(at: slotIndex)
        XCTAssertEqual(project.generatorPool.count, baselineGeneratorCount + 1)
        XCTAssertEqual(project.clipPool.count, baselineClipCount)
        XCTAssertEqual(slot.sourceRef.mode, .clip)
        XCTAssertNil(slot.sourceRef.clipID)
        XCTAssertEqual(slot.sourceRef.generatorID, sourceGeneratorID)
        XCTAssertEqual(slot.sourceRef.modifierGeneratorID, modifier.id)
        XCTAssertFalse(slot.sourceRef.modifierBypassed)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: siblingSlotIndex).sourceRef, siblingBaseline)
    }

    func test_assignModifierGenerator_updates_only_selected_slot_without_creating_source_material() throws {
        var (project, trackID, sourceGeneratorID, _, _, siblingBaseline) = try makeProject()
        let baselineClipCount = project.clipPool.count
        let alternateModifier = GeneratorPoolEntry(
            id: UUID(),
            name: "Alternate Modifier",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .defaultMono
        )
        project.generatorPool.append(alternateModifier)
        project.removeSelectedSlotSource(trackID: trackID, slotIndex: slotIndex)

        project.assignModifierGenerator(alternateModifier.id, to: trackID, slotIndex: slotIndex)

        let slot = project.patternBank(for: trackID).slot(at: slotIndex)
        XCTAssertEqual(project.clipPool.count, baselineClipCount)
        XCTAssertEqual(slot.sourceRef.mode, .clip)
        XCTAssertNil(slot.sourceRef.clipID)
        XCTAssertEqual(slot.sourceRef.generatorID, sourceGeneratorID)
        XCTAssertEqual(slot.sourceRef.modifierGeneratorID, alternateModifier.id)
        XCTAssertFalse(slot.sourceRef.modifierBypassed)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: siblingSlotIndex).sourceRef, siblingBaseline)
    }

    func test_removeModifierGenerator_clears_bypass_without_creating_source_material() throws {
        var (project, trackID, sourceGeneratorID, _, _, siblingBaseline) = try makeProject()
        let baselineClipCount = project.clipPool.count
        project.removeSelectedSlotSource(trackID: trackID, slotIndex: slotIndex)

        project.removeModifierGenerator(from: trackID, slotIndex: slotIndex)

        let slot = project.patternBank(for: trackID).slot(at: slotIndex)
        XCTAssertEqual(project.clipPool.count, baselineClipCount)
        XCTAssertEqual(slot.sourceRef.mode, .clip)
        XCTAssertNil(slot.sourceRef.clipID)
        XCTAssertEqual(slot.sourceRef.generatorID, sourceGeneratorID)
        XCTAssertNil(slot.sourceRef.modifierGeneratorID)
        XCTAssertFalse(slot.sourceRef.modifierBypassed)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: siblingSlotIndex).sourceRef, siblingBaseline)
    }
}
