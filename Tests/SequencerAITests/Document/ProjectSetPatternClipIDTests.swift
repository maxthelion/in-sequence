import Foundation
import XCTest
@testable import SequencerAI

final class ProjectSetPatternClipIDTests: XCTestCase {
    // Helper: project with a track + attached generator + slot 3 bypassed.
    private func projectWithBypassedSlot() throws -> (project: Project, trackID: UUID, generatorID: UUID) {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let entry = try XCTUnwrap(project.attachNewGenerator(to: track.id))
        project.setSlotBypassed(true, trackID: track.id, slotIndex: 3)
        return (project, track.id, entry.id)
    }

    func test_setPatternClipID_on_bypassed_slot_preserves_generatorID() throws {
        var (project, trackID, generatorID) = try projectWithBypassedSlot()
        // Create a second clip to switch to
        let otherClip = ClipPoolEntry(
            id: UUID(),
            name: "Other Clip",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: [60])
        )
        project.clipPool.append(otherClip)

        project.setPatternClipID(otherClip.id, for: trackID, slotIndex: 3)

        let slot = project.patternBank(for: trackID).slot(at: 3)
        XCTAssertEqual(
            slot.sourceRef.generatorID, generatorID,
            "setPatternClipID must preserve the slot's retained generatorID"
        )
        XCTAssertEqual(slot.sourceRef.clipID, otherClip.id, "clipID must be updated to the new clip")
        XCTAssertEqual(slot.sourceRef.mode, .clip, "bypassed slot must remain in clip mode")
    }

    func test_unbypass_after_clip_change_re_engages_attached_generator() throws {
        var (project, trackID, generatorID) = try projectWithBypassedSlot()
        let otherClip = ClipPoolEntry(
            id: UUID(),
            name: "Other Clip",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: [60])
        )
        project.clipPool.append(otherClip)
        project.setPatternClipID(otherClip.id, for: trackID, slotIndex: 3)

        // Un-bypass: re-engage the generator
        project.setSlotBypassed(false, trackID: trackID, slotIndex: 3)

        let slot = project.patternBank(for: trackID).slot(at: 3)
        XCTAssertEqual(slot.sourceRef.mode, .generator, "un-bypassing must flip mode back to generator")
        XCTAssertEqual(slot.sourceRef.generatorID, generatorID, "generatorID must still be the attached generator")
    }
}

final class ProjectPatternSlotClipboardTests: XCTestCase {
    func test_pasteClonesEveryReferencedAssetWithFreshIDs() throws {
        var project = Project.empty
        let trackID = project.selectedTrackID
        let sourceClip = makeClip(name: "Pattern Clip", pitch: 60)
        let generatedClip = makeClip(name: "Generated Source", pitch: 67)
        let generator = makeGenerator(name: "Main Generator")
        let modifier = makeGenerator(name: "Modifier")
        project.clipPool.append(contentsOf: [sourceClip, generatedClip])
        project.generatorPool.append(contentsOf: [generator, modifier])
        setSlot(
            in: &project,
            trackID: trackID,
            slotIndex: 0,
            name: "Source Pattern",
            sourceRef: SourceRef(
                mode: .clip,
                generatorID: generator.id,
                clipID: sourceClip.id,
                sourceClipID: generatedClip.id,
                modifierGeneratorID: modifier.id,
                modifierBypassed: true
            )
        )

        let clipboard = try XCTUnwrap(
            project.detachedPatternSlotClipboard(
                trackIDs: [trackID],
                slotIndex: 0,
                scope: .singleTrack
            )
        )
        XCTAssertEqual(Set(clipboard.items[0].clips.map(\.id)), [sourceClip.id, generatedClip.id])
        XCTAssertEqual(Set(clipboard.items[0].generators.map(\.id)), [generator.id, modifier.id])

        XCTAssertTrue(
            project.pastePatternSlotClipboard(
                clipboard,
                toTrackIDs: [trackID],
                slotIndexes: [4],
                targetScope: .singleTrack
            )
        )
        let firstPaste = project.patternBank(for: trackID).slot(at: 4)
        XCTAssertEqual(firstPaste.name, "Source Pattern")
        XCTAssertEqual(firstPaste.sourceRef.modifierBypassed, true)
        XCTAssertNotEqual(firstPaste.sourceRef.clipID, sourceClip.id)
        XCTAssertNotEqual(firstPaste.sourceRef.sourceClipID, generatedClip.id)
        XCTAssertNotEqual(firstPaste.sourceRef.generatorID, generator.id)
        XCTAssertNotEqual(firstPaste.sourceRef.modifierGeneratorID, modifier.id)
        XCTAssertEqual(
            project.clipEntry(id: try XCTUnwrap(firstPaste.sourceRef.clipID))?.content,
            sourceClip.content
        )
        XCTAssertEqual(
            project.generatorEntry(id: try XCTUnwrap(firstPaste.sourceRef.generatorID))?.params,
            generator.params
        )

        XCTAssertTrue(
            project.pastePatternSlotClipboard(
                clipboard,
                toTrackIDs: [trackID],
                slotIndexes: [5],
                targetScope: .singleTrack
            )
        )
        let secondPaste = project.patternBank(for: trackID).slot(at: 5)
        XCTAssertNotEqual(secondPaste.sourceRef.clipID, firstPaste.sourceRef.clipID)
        XCTAssertNotEqual(secondPaste.sourceRef.sourceClipID, firstPaste.sourceRef.sourceClipID)
        XCTAssertNotEqual(secondPaste.sourceRef.generatorID, firstPaste.sourceRef.generatorID)
        XCTAssertNotEqual(secondPaste.sourceRef.modifierGeneratorID, firstPaste.sourceRef.modifierGeneratorID)

        let pastedClipID = try XCTUnwrap(firstPaste.sourceRef.clipID)
        project.updateClipEntry(id: pastedClipID) { $0.name = "Edited Paste" }
        XCTAssertEqual(project.clipEntry(id: sourceClip.id)?.name, "Pattern Clip")
        XCTAssertEqual(project.clipEntry(id: secondPaste.sourceRef.clipID)?.name, "Pattern Clip")
    }

    func test_pasteRejectsIncompatibleTrackTypeWithoutMutation() throws {
        var project = Project.empty
        let monoTrackID = project.selectedTrackID
        let clipboard = try XCTUnwrap(
            project.detachedPatternSlotClipboard(
                trackIDs: [monoTrackID],
                slotIndex: 0,
                scope: .singleTrack
            )
        )
        project.appendTrack(trackType: .slice)
        let sliceTrackID = project.selectedTrackID
        let clipCount = project.clipPool.count
        let generatorCount = project.generatorPool.count

        XCTAssertFalse(
            project.canPastePatternSlotClipboard(
                clipboard,
                toTrackIDs: [monoTrackID],
                slotIndexes: [2],
                targetScope: .drumKit
            ),
            "Single-track payloads must not enable drum-kit targets, even when each has one track"
        )
        XCTAssertFalse(
            project.canPastePatternSlotClipboard(
                clipboard,
                toTrackIDs: [sliceTrackID],
                slotIndexes: [2],
                targetScope: .singleTrack
            )
        )
        XCTAssertFalse(
            project.pastePatternSlotClipboard(
                clipboard,
                toTrackIDs: [sliceTrackID],
                slotIndexes: [2],
                targetScope: .singleTrack
            )
        )
        XCTAssertEqual(project.clipPool.count, clipCount)
        XCTAssertEqual(project.generatorPool.count, generatorCount)
    }

    func test_drumKitPasteMapsPartsByVoiceTagAndClonesEachTargetSlot() throws {
        var project = Project.empty
        let kickID = project.selectedTrackID
        project.appendTrack(trackType: .monoMelodic)
        let snareID = project.selectedTrackID
        project.tracks[try XCTUnwrap(project.tracks.firstIndex { $0.id == kickID })].voiceTag = "kick"
        project.tracks[try XCTUnwrap(project.tracks.firstIndex { $0.id == snareID })].voiceTag = "snare"

        let kickClip = makeClip(name: "Kick Pattern", pitch: 36)
        let snareClip = makeClip(name: "Snare Pattern", pitch: 38)
        project.clipPool.append(contentsOf: [kickClip, snareClip])
        setSlot(in: &project, trackID: kickID, slotIndex: 0, sourceRef: .clip(kickClip.id))
        setSlot(in: &project, trackID: snareID, slotIndex: 0, sourceRef: .clip(snareClip.id))

        let clipboard = try XCTUnwrap(
            project.detachedPatternSlotClipboard(
                trackIDs: [kickID, snareID],
                slotIndex: 0,
                scope: .drumKit
            )
        )
        XCTAssertTrue(
            project.pastePatternSlotClipboard(
                clipboard,
                toTrackIDs: [snareID, kickID],
                slotIndexes: [2, 3],
                targetScope: .drumKit
            )
        )

        let kickSlot2 = project.patternBank(for: kickID).slot(at: 2)
        let kickSlot3 = project.patternBank(for: kickID).slot(at: 3)
        let snareSlot2 = project.patternBank(for: snareID).slot(at: 2)
        XCTAssertEqual(project.clipEntry(id: kickSlot2.sourceRef.clipID)?.name, "Kick Pattern")
        XCTAssertEqual(project.clipEntry(id: snareSlot2.sourceRef.clipID)?.name, "Snare Pattern")
        XCTAssertNotEqual(kickSlot2.sourceRef.clipID, kickClip.id)
        XCTAssertNotEqual(kickSlot2.sourceRef.clipID, kickSlot3.sourceRef.clipID)
    }

    private func makeClip(name: String, pitch: Int) -> ClipPoolEntry {
        ClipPoolEntry(
            id: UUID(),
            name: name,
            trackType: .monoMelodic,
            content: .stepSequence(
                stepPattern: [true, false, false, false],
                pitches: [pitch]
            )
        )
    }

    private func makeGenerator(name: String) -> GeneratorPoolEntry {
        .makeDefault(
            id: UUID(),
            name: name,
            kind: .monoGenerator,
            trackType: .monoMelodic
        )
    }

    private func setSlot(
        in project: inout Project,
        trackID: UUID,
        slotIndex: Int,
        name: String? = nil,
        sourceRef: SourceRef
    ) {
        guard let bankIndex = project.patternBanks.firstIndex(where: { $0.trackID == trackID }) else {
            return XCTFail("Missing pattern bank")
        }
        project.patternBanks[bankIndex].setSlot(
            TrackPatternSlot(slotIndex: slotIndex, name: name, sourceRef: sourceRef),
            at: slotIndex
        )
    }
}
