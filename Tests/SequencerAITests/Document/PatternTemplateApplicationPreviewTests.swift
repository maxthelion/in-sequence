import Foundation
import XCTest
@testable import SequencerAI

final class PatternTemplateApplicationPreviewTests: XCTestCase {
    private let kickPattern = (0..<16).map { $0 % 4 == 0 }
    private let snarePattern = (0..<16).map { $0 % 8 == 4 }

    private func makeTemplate(patterns: [VoiceTag: [Bool]]? = nil) -> PatternTemplate {
        PatternTemplate(
            id: UUID(),
            name: "Preview Groove",
            patterns: patterns ?? ["kick": kickPattern, "snare": snarePattern, "clap": kickPattern]
        )
    }

    // MARK: - Creation-flow preview (tag + name pairs)

    func test_creationPreview_fillsMatchedTagsAndListsMissingEntries() {
        let preview = PatternTemplateApplicationPreview(
            template: makeTemplate(),
            parts: [
                (tag: "kick", name: "Kick"),
                (tag: "snare", name: "Snare"),
                (tag: "hat-closed", name: "Hat"),
            ]
        )

        XCTAssertEqual(preview.filledPartNames, ["Kick", "Snare"])
        XCTAssertEqual(preview.missingTagLabels, ["Clap"])
        XCTAssertEqual(preview.summary, "Fills Kick, Snare — no Clap entry")
        XCTAssertFalse(preview.requiresOverwriteConfirmation)
    }

    func test_creationPreview_duplicateTagsFillFirstOccurrenceOnly() {
        let preview = PatternTemplateApplicationPreview(
            template: makeTemplate(patterns: ["kick": kickPattern]),
            parts: [
                (tag: "kick", name: "Kick A"),
                (tag: "kick", name: "Kick B"),
            ]
        )

        XCTAssertEqual(preview.filledPartNames, ["Kick A"])
        XCTAssertEqual(preview.duplicateTagSkippedPartNames, ["Kick B"])
    }

    func test_creationPreview_noMatchesSummarizesAsFillsNoParts() {
        let preview = PatternTemplateApplicationPreview(
            template: makeTemplate(patterns: ["shaker": kickPattern, "ride": kickPattern]),
            parts: [(tag: "kick", name: "Kick")]
        )

        XCTAssertEqual(preview.filledPartNames, [])
        XCTAssertEqual(preview.summary, "Fills no parts — no Ride, Shaker entries")
    }

    func test_tagLabelsAreHumanReadable() {
        XCTAssertEqual(PatternTemplateApplicationPreview.tagLabel("hat-closed"), "Hat Closed")
        XCTAssertEqual(PatternTemplateApplicationPreview.tagLabel("kick"), "Kick")
    }

    // MARK: - Group preview (matches Project.applyPatternTemplate)

    private struct GroupFixture {
        var group: TrackGroup
        var tracks: [StepSequenceTrack]
        var patternBanks: [TrackPatternBank]
        var clipPool: [ClipPoolEntry]
    }

    private func makeGroupFixture(
        tags: [(tag: VoiceTag, name: String)] = [
            (tag: "kick", name: "Kick"),
            (tag: "snare", name: "Snare"),
            (tag: "hat-closed", name: "Hat"),
        ]
    ) -> GroupFixture {
        var tracks: [StepSequenceTrack] = []
        var banks: [TrackPatternBank] = []
        var clips: [ClipPoolEntry] = []
        let groupID = TrackGroupID()

        for entry in tags {
            let emptyClip = ClipPoolEntry(
                id: UUID(),
                name: entry.name,
                trackType: .monoMelodic,
                content: .emptyNoteGrid(lengthSteps: 16)
            )
            let track = StepSequenceTrack(
                name: entry.name,
                trackType: .monoMelodic,
                voiceTag: entry.tag,
                pitches: [DrumKitNoteMap.baselineNote],
                stepPattern: Array(repeating: false, count: 16),
                destination: .inheritGroup,
                groupID: groupID,
                velocity: 100,
                gateLength: 4
            )
            clips.append(emptyClip)
            tracks.append(track)
            banks.append(TrackPatternBank.default(for: track, initialClipID: emptyClip.id))
        }

        return GroupFixture(
            group: TrackGroup(
                id: groupID,
                name: "Preview Kit",
                color: "#8AA",
                memberIDs: tracks.map(\.id)
            ),
            tracks: tracks,
            patternBanks: banks,
            clipPool: clips
        )
    }

    private func groupPreview(
        _ fixture: GroupFixture,
        template: PatternTemplate,
        slotIndex: Int = 0
    ) -> PatternTemplateApplicationPreview {
        PatternTemplateApplicationPreview(
            template: template,
            group: fixture.group,
            tracks: fixture.tracks,
            patternBanks: fixture.patternBanks,
            clipPool: fixture.clipPool,
            slotIndex: slotIndex
        )
    }

    func test_groupPreview_emptySlotsFillWithoutOverwriteConfirmation() {
        let fixture = makeGroupFixture()

        let preview = groupPreview(fixture, template: makeTemplate())

        XCTAssertEqual(preview.filledPartNames, ["Kick", "Snare"])
        XCTAssertEqual(preview.missingTagLabels, ["Clap"])
        XCTAssertEqual(preview.overwrittenPartNames, [])
        XCTAssertFalse(preview.requiresOverwriteConfirmation)
    }

    func test_groupPreview_nonEmptySlotRequiresOverwriteConfirmation() throws {
        var fixture = makeGroupFixture()
        let kickClipID = try XCTUnwrap(
            fixture.patternBanks[0].slot(at: 0).sourceRef.clipID
        )
        let clipIndex = try XCTUnwrap(fixture.clipPool.firstIndex(where: { $0.id == kickClipID }))
        fixture.clipPool[clipIndex].content = .stepSequence(
            stepPattern: kickPattern,
            pitches: [DrumKitNoteMap.baselineNote]
        )

        let preview = groupPreview(fixture, template: makeTemplate())

        XCTAssertEqual(preview.overwrittenPartNames, ["Kick"])
        XCTAssertTrue(preview.requiresOverwriteConfirmation)
        XCTAssertEqual(preview.filledPartNames, ["Kick", "Snare"])
    }

    func test_groupPreview_generatorSlotIsListedAsSkipped() {
        var fixture = makeGroupFixture()
        var kickBank = fixture.patternBanks[0]
        kickBank.setSlot(
            TrackPatternSlot(slotIndex: 0, sourceRef: .generator(UUID())),
            at: 0
        )
        fixture.patternBanks[0] = kickBank

        let preview = groupPreview(fixture, template: makeTemplate())

        XCTAssertEqual(preview.generatorSkippedPartNames, ["Kick"])
        XCTAssertEqual(preview.filledPartNames, ["Snare"])
        XCTAssertFalse(
            preview.missingTagLabels.contains("Kick"),
            "A generator-consumed tag is skipped, not missing"
        )
    }

    func test_groupPreview_duplicateTagsFillFirstOccurrenceOnly() {
        let fixture = makeGroupFixture(tags: [
            (tag: "kick", name: "Kick A"),
            (tag: "kick", name: "Kick B"),
        ])

        let preview = groupPreview(fixture, template: makeTemplate(patterns: ["kick": kickPattern]))

        XCTAssertEqual(preview.filledPartNames, ["Kick A"])
        XCTAssertEqual(preview.duplicateTagSkippedPartNames, ["Kick B"])
    }

    /// The preview's matching must agree with the real apply: whatever the
    /// preview says fills is exactly what `Project.applyPatternTemplate`
    /// materializes.
    func test_groupPreview_agreesWithProjectApply() throws {
        var project = Project.empty
        let plan = DrumGroupPlan(
            name: "Agree Kit",
            color: "#8AA",
            members: [
                DrumGroupPlan.Member(tag: "kick", trackName: "Kick"),
                DrumGroupPlan.Member(tag: "snare", trackName: "Snare"),
                DrumGroupPlan.Member(tag: "tom-low", trackName: "Tom"),
            ]
        )
        let groupID = try XCTUnwrap(
            project.addDrumGroup(plan: plan, library: AudioSampleLibrary(libraryRoot: FileManager.default.temporaryDirectory))
        )
        let group = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID }))
        let template = makeTemplate()

        let preview = PatternTemplateApplicationPreview(
            template: template,
            group: group,
            tracks: project.tracks,
            patternBanks: project.patternBanks,
            clipPool: project.clipPool,
            slotIndex: 0
        )

        let clipCountBefore = project.clipPool.count
        project.applyPatternTemplate(template, toGroup: groupID, slotIndex: 0)

        XCTAssertEqual(
            project.clipPool.count - clipCountBefore,
            preview.filledPartNames.count,
            "Apply materializes one fresh clip per previewed fill"
        )
    }
}
