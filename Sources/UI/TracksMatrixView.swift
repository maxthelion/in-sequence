import SwiftUI

struct TracksMatrixView: View {
    @Binding var document: SeqAIDocument
    let onOpenTrack: () -> Void

    @State private var isPresentingCreateTrack = false
    @State private var collapsedGroupIDs: Set<TrackGroupID> = []

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 14)
    ]

    private var groupedSections: [GroupedTrackSection] {
        document.model.trackGroups.compactMap { group in
            let members = document.model.tracksInGroup(group.id)
            guard !members.isEmpty else {
                return nil
            }
            return GroupedTrackSection(group: group, members: members)
        }
    }

    private var ungroupedTracks: [StepSequenceTrack] {
        document.model.tracks.filter { $0.groupID == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Tracks",
                eyebrow: "\(document.model.tracks.count) tracks • flat matrix with grouped drum-kit bundles",
                accent: StudioTheme.cyan
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    actionBar

                    if document.model.tracks.isEmpty {
                        StudioPlaceholderTile(
                            title: "No Tracks Yet",
                            detail: "Create a mono, poly, slice, or drum-kit bundle to start building the matrix.",
                            accent: StudioTheme.cyan
                        )
                    } else {
                        matrixSections
                    }
                }
            }
        }
        .padding(20)
        .sheet(isPresented: $isPresentingCreateTrack) {
            CreateTrackSheet(document: $document, onOpenTrack: onOpenTrack)
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
                document.model.appendTrack(trackType: .monoMelodic)
                onOpenTrack()
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.cyan)

            Button("Add Poly") {
                document.model.appendTrack(trackType: .polyMelodic)
                onOpenTrack()
            }
            .buttonStyle(.bordered)

            Button("Add Slice") {
                document.model.appendTrack(trackType: .slice)
                onOpenTrack()
            }
            .buttonStyle(.bordered)

            Menu("Add Drum Kit") {
                ForEach(DrumKitPreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) {
                        _ = document.model.addDrumKit(preset)
                        onOpenTrack()
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }

    private var matrixSections: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !ungroupedTracks.isEmpty {
                TrackSectionShell(
                    title: "Ungrouped",
                    detail: "\(ungroupedTracks.count) standalone track\(ungroupedTracks.count == 1 ? "" : "s")",
                    accent: StudioTheme.cyan
                ) {
                    tracksGrid(ungroupedTracks, group: nil)
                }
            }

            ForEach(groupedSections) { section in
                GroupSectionView(
                    section: section,
                    isCollapsed: collapsedGroupIDs.contains(section.id),
                    toggleCollapse: { toggleCollapse(for: section.id) },
                    grid: { tracksGrid(section.members, group: section.group) }
                )
            }
        }
    }

    @ViewBuilder
    private func tracksGrid(_ tracks: [StepSequenceTrack], group: TrackGroup?) -> some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(tracks, id: \.id) { track in
                TrackMatrixCard(
                    track: track,
                    group: group,
                    patternIndex: document.model.selectedPatternIndex(for: track.id),
                    isSelected: track.id == document.model.selectedTrackID
                ) {
                    document.model.selectTrack(id: track.id)
                    onOpenTrack()
                }
            }
        }
    }

    private func toggleCollapse(for groupID: TrackGroupID) {
        if collapsedGroupIDs.contains(groupID) {
            collapsedGroupIDs.remove(groupID)
        } else {
            collapsedGroupIDs.insert(groupID)
        }
    }
}

private struct GroupedTrackSection: Identifiable {
    let group: TrackGroup
    let members: [StepSequenceTrack]

    var id: TrackGroupID { group.id }
}

private struct TrackSectionShell<Content: View>: View {
    let title: String
    let detail: String
    let accent: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(StudioTheme.text)

                Rectangle()
                    .fill(accent)
                    .frame(width: 34, height: 3)
                    .clipShape(Capsule())

                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }

            content
        }
    }
}

private struct GroupSectionView<Grid: View>: View {
    let section: GroupedTrackSection
    let isCollapsed: Bool
    let toggleCollapse: () -> Void
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
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)

                        Text("\(section.members.count) tracks")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(accent.opacity(0.18), in: Capsule())
                            .foregroundStyle(accent)
                    }

                    Text(section.group.sharedDestination?.summary ?? "Shared destination not assigned")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer()

                Button(isCollapsed ? "Expand" : "Collapse", action: toggleCollapse)
                    .buttonStyle(.bordered)
            }

            if isCollapsed {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(section.members, id: \.id) { track in
                            Text(track.name)
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.04), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(accent.opacity(0.35), lineWidth: 1)
                                )
                                .foregroundStyle(StudioTheme.text)
                        }
                    }
                }
            } else {
                grid
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(accent.opacity(0.16), lineWidth: 1)
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
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                    }

                    Spacer(minLength: 0)
                }

                if let group {
                    Text(group.name.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(accent.opacity(0.14), in: Capsule())
                } else {
                    Text(track.defaultDestination.summary)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.16) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.55) : StudioTheme.border, lineWidth: isSelected ? 2 : 1)
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
            .background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(accent.opacity(0.45), lineWidth: 1)
            )
    }
}

private struct CreateTrackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var document: SeqAIDocument
    let onOpenTrack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Create Track")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)

            Text("Choose the kind of track to append to the matrix. You can rename and edit the destination in the Track workspace right after creation.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
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
            document.model.appendTrack(trackType: type)
            dismiss()
            onOpenTrack()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                Text(detail)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .padding(16)
            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
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
