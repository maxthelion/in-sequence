import SwiftUI

struct TracksMatrixView: View {
    @Binding var document: SeqAIDocument
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session
    let onOpenTrack: () -> Void

    @State private var isPresentingCreateTrack = false
    @State private var isPresentingAddDrumGroup = false

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 14)
    ]

    private var groupedSections: [GroupedTrackSection] {
        session.store.trackGroups.compactMap { group in
            let members = session.store.tracksInGroup(group.id)
            guard !members.isEmpty else {
                return nil
            }
            return GroupedTrackSection(group: group, members: members)
        }
    }

    private var ungroupedTracks: [StepSequenceTrack] {
        session.store.tracks.filter { $0.groupID == nil }
    }

    var body: some View {
        let tracks = session.store.tracks
        let selectedTrackID = session.store.selectedTrackID
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Tracks",
                accent: StudioTheme.cyan
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    actionBar

                    if tracks.isEmpty {
                        StudioPlaceholderTile(
                            title: "No Tracks Yet",
                            detail: "Create a mono, poly, slice, or drum-kit bundle to start building the matrix.",
                            accent: StudioTheme.cyan
                        )
                    } else {
                        matrixSections(tracks: tracks, selectedTrackID: selectedTrackID)
                    }
                }
            }
        }
        .padding(20)
        .sheet(isPresented: $isPresentingCreateTrack) {
            CreateTrackSheet(document: $document, onOpenTrack: onOpenTrack)
        }
        .sheet(isPresented: $isPresentingAddDrumGroup) {
            AddDrumGroupSheet(
                auInstruments: engineController.availableAudioInstruments,
                onCreate: { plan in
                    _ = session.addDrumGroup(plan: plan)
                    isPresentingAddDrumGroup = false
                    onOpenTrack()
                },
                onCancel: {
                    isPresentingAddDrumGroup = false
                }
            )
            .presentationBackground(.clear)
        }
    }

    private var actionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                createTrackButtons
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                createTrackButtons
            }
        }
    }

    private var createTrackButtons: some View {
        Group {
            Button("Add Mono") {
                session.appendTrack(trackType: .monoMelodic)
                onOpenTrack()
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.cyan)

            Button("Add Poly") {
                session.appendTrack(trackType: .polyMelodic)
                onOpenTrack()
            }
            .buttonStyle(.bordered)

            Button("Add Slice") {
                session.appendTrack(trackType: .slice)
                onOpenTrack()
            }
            .buttonStyle(.bordered)

            Button("Add Drum Group") {
                isPresentingAddDrumGroup = true
            }
            .buttonStyle(.bordered)
        }
    }

    private func matrixSections(tracks: [StepSequenceTrack], selectedTrackID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if !ungroupedTracks.isEmpty {
                tracksGrid(ungroupedTracks, group: nil, selectedTrackID: selectedTrackID)
            }

            ForEach(groupedSections) { section in
                GroupSectionView(
                    section: section,
                    grid: { tracksGrid(section.members, group: section.group, selectedTrackID: selectedTrackID) }
                )
            }
        }
    }

    @ViewBuilder
    private func tracksGrid(_ tracks: [StepSequenceTrack], group: TrackGroup?, selectedTrackID: UUID) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(tracks, id: \.id) { track in
                TrackMatrixCard(
                    track: track,
                    group: group,
                    patternIndex: session.store.selectedPatternIndex(for: track.id),
                    isSelected: track.id == selectedTrackID
                ) {
                    session.setSelectedTrackID(track.id)
                    onOpenTrack()
                }
            }
        }
    }

}

private struct GroupedTrackSection: Identifiable {
    let group: TrackGroup
    let members: [StepSequenceTrack]

    var id: TrackGroupID { group.id }
}

private struct GroupSectionView<Grid: View>: View {
    let section: GroupedTrackSection
    @ViewBuilder let grid: Grid

    private var accent: Color {
        Color(hex: section.group.color) ?? StudioTheme.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(section.group.name)
                            .studioText(.title)
                            .foregroundStyle(StudioTheme.text)

                        Text("\(section.members.count) tracks")
                            .studioText(.eyebrowBold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(accent.opacity(StudioOpacity.selectedFill), in: Capsule())
                            .foregroundStyle(accent)
                    }

                    Text(section.group.sharedDestination?.summary ?? "Shared destination not assigned")
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }
            }

            grid
        }
        .padding(16)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.hoverFill), lineWidth: 1)
        )
    }
}

private struct TrackMatrixCard: View {
    let track: StepSequenceTrack
    let group: TrackGroup?
    let patternIndex: Int
    let isSelected: Bool
    let onTap: () -> Void

    private var accent: Color {
        if let group {
            return Color(hex: group.color) ?? StudioTheme.cyan
        }
        switch track.trackType {
        case .monoMelodic:
            return StudioTheme.cyan
        case .polyMelodic:
            return StudioTheme.amber
        case .slice:
            return StudioTheme.violet
        }
    }

    private var typeLabel: String {
        track.trackType.label.uppercased()
    }

    private var destinationLabel: String {
        if case .inheritGroup = track.destination {
            return group?.sharedDestination?.kindLabel ?? "GROUP"
        }
        return track.destination.kindLabel
    }

    private var pitchOffsetLabel: String? {
        guard let group, let offset = group.noteMapping[track.id], offset != 0 else {
            return nil
        }
        return offset > 0 ? "+\(offset)" : "\(offset)"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TrackTypeBadge(trackType: track.trackType, accent: accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            Text(typeLabel)
                            Text("P\(patternIndex + 1)")
                            Text(destinationLabel)
                            if let pitchOffsetLabel {
                                Text(pitchOffsetLabel)
                            }
                        }
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                    }

                    Spacer(minLength: 0)
                }

                if let group {
                    Text(group.name.uppercased())
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(StudioOpacity.faintStroke), in: Capsule())
                } else {
                    Text(track.defaultDestination.summary)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .fill(isSelected ? accent.opacity(StudioOpacity.hoverFill) : Color.white.opacity(StudioOpacity.subtleFill))
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(isSelected ? accent.opacity(StudioOpacity.accentFill) : StudioTheme.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct TrackTypeBadge: View {
    let trackType: TrackType
    let accent: Color

    private var icon: String {
        switch trackType {
        case .monoMelodic:
            return "waveform.path"
        case .polyMelodic:
            return "pianokeys"
        case .slice:
            return "waveform"
        }
    }

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(StudioTheme.text)
            .frame(width: 30, height: 30)
            .background(accent.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
            )
    }
}

private struct CreateTrackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SequencerDocumentSession.self) private var session
    @Binding var document: SeqAIDocument
    let onOpenTrack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create Track")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)

            Text("Choose the kind of track to append to the matrix. You can rename and edit the destination in the Track workspace right after creation.")
                .studioText(.subtitleMuted)
                .foregroundStyle(StudioTheme.mutedText)

            HStack(spacing: 12) {
                createButton(title: "Mono", detail: "Single melodic lane", type: .monoMelodic, accent: StudioTheme.cyan)
                createButton(title: "Poly", detail: "Chord-capable lane", type: .polyMelodic, accent: StudioTheme.amber)
                createButton(title: "Slice", detail: "Sample/slice trigger lane", type: .slice, accent: StudioTheme.violet)
            }
        }
        .padding(24)
        .frame(minWidth: 560)
        .background(StudioTheme.chrome)
    }

    private func createButton(title: String, detail: String, type: TrackType, accent: Color) -> some View {
        Button {
            session.appendTrack(trackType: type)
            dismiss()
            onOpenTrack()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .studioText(.title)
                    .foregroundStyle(StudioTheme.text)
                Text(detail)
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(16)
            .background(accent.opacity(StudioOpacity.mutedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(accent.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private extension Color {
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        string = string.replacingOccurrences(of: "#", with: "")
        guard string.count == 6, let value = UInt64(string, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0
        )
    }
}
