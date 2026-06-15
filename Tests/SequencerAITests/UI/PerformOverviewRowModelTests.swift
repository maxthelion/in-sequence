import SwiftUI
import XCTest
@testable import SequencerAI

/// Row-model anatomy for the perform-overview dashboard (wireframes §9 + §1):
/// one row per ungrouped track and one row per kit group, kit rows carrying
/// the single violet accent and aggregating their parts, audio-in rows
/// exposing the monitor cell, and the cell order pattern/fill/repeat/mute for
/// instruments and kits. These pin the pure presentation contract the
/// dashboard renders, so the layout can be reasoned about without hosting.
@MainActor
final class PerformOverviewRowModelTests: XCTestCase {

    private func track(
        _ name: String,
        type: TrackType = .monoMelodic,
        groupID: TrackGroupID? = nil
    ) -> StepSequenceTrack {
        StepSequenceTrack(
            name: name,
            trackType: type,
            pitches: [60],
            stepPattern: Array(repeating: false, count: 16),
            stepAccents: Array(repeating: false, count: 16),
            groupID: groupID,
            velocity: 96,
            gateLength: 4
        )
    }

    func test_rows_oneRowPerUngroupedTrackInProjectOrder() {
        let lead = track("Lead", type: .monoMelodic)
        let pad = track("Pad", type: .polyMelodic)
        let chop = track("Chop", type: .slice)

        let rows = PerformOverviewRowModel.rows(tracks: [lead, pad, chop], groups: [])

        XCTAssertEqual(rows.map(\.title), ["Lead", "Pad", "Chop"])
        XCTAssertTrue(rows.allSatisfy { $0.kind == .instrument })
        XCTAssertEqual(rows.map { $0.trackIDs }, [[lead.id], [pad.id], [chop.id]])
        XCTAssertTrue(rows.allSatisfy { $0.parts.isEmpty })
        XCTAssertEqual(rows.map(\.id), [lead.id.uuidString, pad.id.uuidString, chop.id.uuidString])
    }

    func test_rows_oneKitRowPerGroup_collapsesMembersIntoVioletRowWithPartStrip() {
        let groupID = UUID()
        let kick = track("Kick", groupID: groupID)
        let snare = track("Snare", groupID: groupID)
        let hat = track("Hat", groupID: groupID)
        let group = TrackGroup(id: groupID, name: "Kit", memberIDs: [kick.id, snare.id, hat.id])

        let rows = PerformOverviewRowModel.rows(tracks: [kick, snare, hat], groups: [group])

        XCTAssertEqual(rows.count, 1, "all kit members collapse to ONE row")
        let kitRow = rows[0]
        XCTAssertEqual(kitRow.kind, .kit)
        XCTAssertEqual(kitRow.title, "Kit")
        XCTAssertNil(kitRow.trackType, "kit rows have no single track-type identity")
        XCTAssertEqual(kitRow.accent, StudioTheme.violet, "kit row carries the ONE violet accent (§1)")
        XCTAssertEqual(kitRow.trackIDs, [kick.id, snare.id, hat.id], "row fans out to every member")
        XCTAssertEqual(kitRow.parts.map(\.name), ["Kick", "Snare", "Hat"], "part strip aggregates members")
        XCTAssertEqual(kitRow.parts.map(\.id), [kick.id, snare.id, hat.id])
        XCTAssertEqual(kitRow.id, groupID.uuidString)
    }

    func test_rows_orderingIsUngroupedFirstThenKits() {
        let groupID = UUID()
        let lead = track("Lead")
        let kick = track("Kick", groupID: groupID)
        let snare = track("Snare", groupID: groupID)
        let group = TrackGroup(id: groupID, name: "Kit", memberIDs: [kick.id, snare.id])

        // Kit members appear before the ungrouped track in the source array —
        // ordering must still place ungrouped rows first, then kit rows.
        let rows = PerformOverviewRowModel.rows(tracks: [kick, snare, lead], groups: [group])

        XCTAssertEqual(rows.map(\.kind), [.instrument, .kit])
        XCTAssertEqual(rows.map(\.title), ["Lead", "Kit"])
    }

    func test_rows_emptyGroupsAreSkipped() {
        let lead = track("Lead")
        let emptyGroup = TrackGroup(id: UUID(), name: "Empty Kit", memberIDs: [])

        let rows = PerformOverviewRowModel.rows(tracks: [lead], groups: [emptyGroup])

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].kind, .instrument)
    }

    func test_audioInputTrack_becomesAudioInputRowExposingMonitorCell() {
        let mic = track("Mic In", type: .audioInput)

        let rows = PerformOverviewRowModel.rows(tracks: [mic], groups: [])

        XCTAssertEqual(rows.count, 1)
        let row = rows[0]
        XCTAssertEqual(row.kind, .audioInput)
        XCTAssertEqual(row.cells, [.monitor, .mute], "audio-in rows are monitor + mute only this slice")
        XCTAssertEqual(row.accent, StudioTheme.success)
    }

    func test_cellOrdering_isPatternFillRepeatMuteForInstrumentsAndKits() {
        let lead = track("Lead")
        let groupID = UUID()
        let kick = track("Kick", groupID: groupID)
        let group = TrackGroup(id: groupID, name: "Kit", memberIDs: [kick.id])

        let rows = PerformOverviewRowModel.rows(tracks: [lead, kick], groups: [group])

        for row in rows where row.kind == .instrument || row.kind == .kit {
            XCTAssertEqual(
                row.cells,
                [.pattern, .fill, .noteRepeat, .mute],
                "instrument/kit cell order is pattern/fill/repeat/mute (\(row.title))"
            )
        }
    }

    func test_instrumentAccents_followTrackTypeIdentity() {
        XCTAssertEqual(PerformOverviewRowModel.rows(tracks: [track("Mono", type: .monoMelodic)], groups: [])[0].accent, StudioTheme.cyan)
        XCTAssertEqual(PerformOverviewRowModel.rows(tracks: [track("Poly", type: .polyMelodic)], groups: [])[0].accent, StudioTheme.amber)
        XCTAssertEqual(PerformOverviewRowModel.rows(tracks: [track("Slice", type: .slice)], groups: [])[0].accent, StudioTheme.violet)
    }

    func test_primaryTrackID_isFirstMember() {
        let groupID = UUID()
        let kick = track("Kick", groupID: groupID)
        let snare = track("Snare", groupID: groupID)
        let group = TrackGroup(id: groupID, name: "Kit", memberIDs: [kick.id, snare.id])

        let kitRow = PerformOverviewRowModel.rows(tracks: [kick, snare], groups: [group])[0]
        XCTAssertEqual(kitRow.primaryTrackID, kick.id)
    }

    // MARK: - Edit-set fanout

    func test_recipientTrackIDs_lonelyRowLandsOnItself() {
        let a = UUID(), b = UUID()
        var selection = TrackPerformSelectionState()
        selection.add(a)

        let recipients = PerformOverviewRowModel.recipientTrackIDs(
            rowTrackIDs: [a],
            orderedTrackIDs: [a, b],
            selection: selection
        )
        XCTAssertEqual(recipients, [a], "a row whose set does not reach beyond it lands on the row alone")
    }

    func test_recipientTrackIDs_rowInLargerSetFansOutToWholeSet() {
        let a = UUID(), b = UUID(), c = UUID()
        var selection = TrackPerformSelectionState()
        selection.add(a)
        selection.add(b)

        let recipients = PerformOverviewRowModel.recipientTrackIDs(
            rowTrackIDs: [a],
            orderedTrackIDs: [a, b, c],
            selection: selection
        )
        XCTAssertEqual(recipients, [a, b], "tap on a selected row fans out to the whole edit set, in project order")
    }

    func test_recipientTrackIDs_partiallySelectedRowLandsOnRow() {
        let a = UUID(), b = UUID(), c = UUID()
        var selection = TrackPerformSelectionState()
        // Only one of the two row members is selected, so the row is not
        // "fully in the set" and the tap stays local.
        selection.add(a)
        selection.add(c)

        let recipients = PerformOverviewRowModel.recipientTrackIDs(
            rowTrackIDs: [a, b],
            orderedTrackIDs: [a, b, c],
            selection: selection
        )
        XCTAssertEqual(recipients, [a, b])
    }

    // MARK: - Monitor label

    func test_monitorLabel_mapsRuntimeMonitorMode() {
        XCTAssertEqual(PerformOverviewRowModel.monitorLabel(.input), "LIVE")
        XCTAssertEqual(PerformOverviewRowModel.monitorLabel(.loop), "BUFFER")
        XCTAssertEqual(PerformOverviewRowModel.monitorLabel(nil), "—")
    }
}
