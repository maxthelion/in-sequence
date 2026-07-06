import SwiftUI

/// One column slot in a perform-overview row (wireframes §9). The model
/// names which controls a row composes so tests can pin the anatomy per
/// track type without rendering.
enum PerformOverviewCell: String, Equatable {
    /// Current pattern chip; tap cycles the pattern (the perform pattern
    /// grammar from the cards).
    case pattern
    /// Audio-in monitor state (Live/Buffer) — patterns-own-source (§4) is
    /// deferred, so this column is a readout, not a switch.
    case monitor
    /// Quantise-aware runtime fill (slice 2 grammar).
    case fill
    /// Runtime note repeat (existing perform control).
    case noteRepeat
    /// Quantise-aware mute toggle (slice 2 grammar).
    case mute
}

/// A part-toggle dot on a kit row: one drum part on/off (mute-layer backed).
struct PerformOverviewPartModel: Identifiable, Equatable {
    let id: UUID
    let name: String
}

/// One row of the perform-mode tracks dashboard: every track (or kit) as a
/// single line of its playable controls (wireframes §9 — the overview IS the
/// perform-mode tracks surface).
struct PerformOverviewRowModel: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Mono / poly / slice track — pattern + fill + repeat + mute.
        case instrument
        /// A drum kit group — ONE row in ONE colour (wireframes §1: the six
        /// part colours collapse), plus the part-toggle strip.
        case kit
        /// Audio-in track — monitor readout + mute only this slice.
        case audioInput
    }

    let id: String
    let kind: Kind
    let title: String
    /// Track type for instrument/audio-in rows (identity accent); nil for kits.
    let trackType: TrackType?
    /// Resolved row identity hue. Type does not choose colour.
    let accentHex: String
    /// Every track this row's controls fan out to (kit = all members).
    let trackIDs: [UUID]
    /// Kit rows: the per-part on/off strip; empty for other kinds.
    let parts: [PerformOverviewPartModel]

    var primaryTrackID: UUID { trackIDs[0] }

    var cells: [PerformOverviewCell] {
        switch kind {
        case .instrument, .kit:
            return [.pattern, .fill, .noteRepeat, .mute]
        case .audioInput:
            return [.monitor, .mute]
        }
    }

    var accent: Color {
        StudioTheme.color(hex: accentHex) ?? StudioTheme.transportAccent
    }

    /// Row order matches the setup matrix: ungrouped tracks first (project
    /// order), then one row per kit in group order.
    static func rows(tracks: [StepSequenceTrack], groups: [TrackGroup]) -> [PerformOverviewRowModel] {
        var rows: [PerformOverviewRowModel] = []

        for track in tracks where track.groupID == nil {
            rows.append(
                PerformOverviewRowModel(
                    id: track.id.uuidString,
                    kind: track.trackType == .audioInput ? .audioInput : .instrument,
                    title: track.name,
                    trackType: track.trackType,
                    accentHex: TrackPalette.identityHex(for: track.id),
                    trackIDs: [track.id],
                    parts: []
                )
            )
        }

        for group in groups {
            let members = tracks.filter { $0.groupID == group.id }
            guard !members.isEmpty else { continue }
            rows.append(
                PerformOverviewRowModel(
                    id: group.id.uuidString,
                    kind: .kit,
                    title: group.name,
                    trackType: nil,
                    accentHex: TrackPalette.isValidHex(group.color) ? group.color : TrackPalette.identityHex(for: group.id),
                    trackIDs: members.map(\.id),
                    parts: members.map { PerformOverviewPartModel(id: $0.id, name: $0.name) }
                )
            )
        }

        return rows
    }

    /// Edit-set fanout for a row tap (the card multiselect contract, lifted
    /// to rows): when every track in the row is in the edit set and the set
    /// reaches beyond the row, the tap lands on the whole set; otherwise it
    /// lands on the row alone.
    static func recipientTrackIDs(
        rowTrackIDs: [UUID],
        orderedTrackIDs: [UUID],
        selection: TrackPerformSelectionState
    ) -> [UUID] {
        let rowSelected = rowTrackIDs.allSatisfy { selection.contains($0) }
        guard rowSelected, selection.count > rowTrackIDs.count else {
            return rowTrackIDs
        }
        let recipients = orderedTrackIDs.filter { selection.contains($0) }
        return recipients.isEmpty ? rowTrackIDs : recipients
    }

    /// Audio-in monitor readout: Live (input) vs Buffer (recorded loop).
    /// Nil runtime (engine not running / no input route) reads as a dash.
    static func monitorLabel(_ mode: EngineController.AudioInputMonitorMode?) -> String {
        switch mode {
        case .input:
            return "LIVE"
        case .loop:
            return "BUFFER"
        case nil:
            return "—"
        }
    }
}
