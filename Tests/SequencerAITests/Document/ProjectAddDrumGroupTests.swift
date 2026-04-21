import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAddDrumGroupTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ["kick", "snare", "hatClosed", "clap", "ride"].forEach(makeCategory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    func test_empty_members_returns_nil_and_leaves_project_unchanged() {
        var project = Project.empty
        let snapshot = project
        var plan = DrumGroupPlan.blankDefault
        plan.members = []

        let result = project.addDrumGroup(plan: plan, library: testLibrary)

        XCTAssertNil(result)
        XCTAssertEqual(project.tracks, snapshot.tracks)
        XCTAssertEqual(project.trackGroups, snapshot.trackGroups)
        XCTAssertEqual(project.clipPool, snapshot.clipPool)
    }

    func test_blankDefault_creates_four_tracks_named_kick_snare_hat_clap() {
        var project = Project.empty
        let initialTrackCount = project.tracks.count

        let groupID = project.addDrumGroup(plan: .blankDefault, library: testLibrary)

        XCTAssertNotNil(groupID)
        XCTAssertEqual(project.tracks.count, initialTrackCount + 4)
        XCTAssertEqual(Array(project.tracks.suffix(4).map(\.name)), ["Kick", "Snare", "Hat", "Clap"])
    }

    func test_blankDefault_creates_a_group_with_no_shared_destination() {
        var project = Project.empty

        let groupID = project.addDrumGroup(plan: .blankDefault, library: testLibrary)

        guard let groupID, let group = project.trackGroups.first(where: { $0.id == groupID }) else {
            return XCTFail("expected a new group to exist")
        }
        XCTAssertNil(group.sharedDestination)
        XCTAssertEqual(group.memberIDs.count, 4)
        XCTAssertEqual(group.color, "#8AA")
        XCTAssertEqual(group.name, "Drum Group")
    }

    func test_blankDefault_all_clips_have_all_false_step_patterns() {
        var project = Project.empty

        _ = project.addDrumGroup(plan: .blankDefault, library: testLibrary)

        let newClips = project.clipPool.suffix(4)
        for clip in newClips {
            guard case let .stepSequence(stepPattern, _) = clip.content else {
                return XCTFail("expected .stepSequence content")
            }
            XCTAssertTrue(stepPattern.allSatisfy { $0 == false }, "blank clip should be all-false")
        }
    }

    func test_templated_kit808_seeds_match_preset_patterns_when_prepopulate_on() {
        var project = Project.empty
        let plan = DrumGroupPlan.templated(from: .kit808)

        _ = project.addDrumGroup(plan: plan, library: testLibrary)

        let newClips = Array(project.clipPool.suffix(plan.members.count))
        for (clip, planMember) in zip(newClips, plan.members) {
            guard case let .stepSequence(stepPattern, _) = clip.content else {
                return XCTFail("expected .stepSequence content")
            }
            XCTAssertEqual(stepPattern, planMember.seedPattern)
        }
    }

    func test_templated_kit808_with_prepopulate_off_produces_empty_clips() {
        var project = Project.empty
        var plan = DrumGroupPlan.templated(from: .kit808)
        plan.prepopulateClips = false

        _ = project.addDrumGroup(plan: plan, library: testLibrary)

        let newClips = Array(project.clipPool.suffix(plan.members.count))
        for clip in newClips {
            guard case let .stepSequence(stepPattern, _) = clip.content else {
                return XCTFail("expected .stepSequence content")
            }
            XCTAssertTrue(stepPattern.allSatisfy { $0 == false })
        }
    }

    func test_shared_destination_with_all_routed_sets_inheritGroup_on_every_member() {
        var project = Project.empty
        var plan = DrumGroupPlan.templated(from: .kit808)
        plan.sharedDestination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)

        _ = project.addDrumGroup(plan: plan, library: testLibrary)

        let newTracks = Array(project.tracks.suffix(plan.members.count))
        for track in newTracks {
            XCTAssertEqual(track.destination, .inheritGroup, "track=\(track.name)")
        }
        guard let group = project.trackGroups.last else {
            return XCTFail("expected a new group")
        }
        XCTAssertEqual(group.sharedDestination, .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0))
    }

    func test_shared_destination_with_mixed_routing_respects_per_member_flag() {
        var project = Project.empty
        var plan = DrumGroupPlan.templated(from: .kit808)
        plan.sharedDestination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        for index in plan.members.indices {
            plan.members[index].routesToShared = index < 2
        }

        _ = project.addDrumGroup(plan: plan, library: testLibrary)

        let newTracks = Array(project.tracks.suffix(plan.members.count))
        XCTAssertEqual(newTracks[0].destination, .inheritGroup)
        XCTAssertEqual(newTracks[1].destination, .inheritGroup)
        XCTAssertNotEqual(newTracks[2].destination, .inheritGroup)
        XCTAssertNotEqual(newTracks[3].destination, .inheritGroup)
    }

    func test_no_shared_destination_gives_every_member_a_per_voice_default() {
        var project = Project.empty

        _ = project.addDrumGroup(plan: .templated(from: .kit808), library: testLibrary)

        let newTracks = Array(project.tracks.suffix(4))
        for track in newTracks {
            XCTAssertNotEqual(track.destination, .inheritGroup)
            XCTAssertNotEqual(track.destination, .none)
        }
    }

    func test_each_member_gets_one_clip_pool_entry_and_one_pattern_bank() {
        var project = Project.empty
        let initialClipCount = project.clipPool.count
        let initialBankCount = project.patternBanks.count

        _ = project.addDrumGroup(plan: .templated(from: .kit808), library: testLibrary)

        XCTAssertEqual(project.clipPool.count, initialClipCount + 4)
        XCTAssertEqual(project.patternBanks.count, initialBankCount + 4)
    }

    func test_selected_track_becomes_first_new_member() {
        var project = Project.empty

        _ = project.addDrumGroup(plan: .templated(from: .kit808), library: testLibrary)

        let firstNewTrackID = project.tracks.suffix(4).first?.id
        XCTAssertEqual(project.selectedTrackID, firstNewTrackID)
    }

    private var testLibrary: AudioSampleLibrary {
        AudioSampleLibrary(libraryRoot: libraryRoot)
    }

    private func makeCategory(_ name: String) throws {
        let directory = libraryRoot.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("\(name)-default.wav"))
    }
}
