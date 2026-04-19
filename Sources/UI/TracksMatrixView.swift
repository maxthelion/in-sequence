import SwiftUI

struct TracksMatrixView: View {
    @Binding var document: SeqAIDocument
    let onOpenTrack: () -> Void

    @State private var isPresentingCreateTrack = false

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 14)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            StudioPanel(
                title: "Tracks",
                eyebrow: "\(document.model.tracks.count) track\(document.model.tracks.count == 1 ? "" : "s") • flat matrix with group tinting",
                accent: StudioTheme.cyan
            ) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Button("Add Track") {
                            isPresentingCreateTrack = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StudioTheme.cyan)

                        Menu("Add Drum Kit") {
                            ForEach(DrumKitPreset.allCases, id: \.self) { preset in
                                Button(preset.displayName) {
                                    _ = document.model.addDrumKit(preset)
                                    onOpenTrack()
                                }
                            }
                        }
                        .buttonStyle(.bordered)

                        Spacer()
                    }

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(document.model.tracks, id: \.id) { track in
                            TrackMatrixCard(
                                track: track,
                                group: document.model.group(for: track.id),
                                isSelected: track.id == document.model.selectedTrackID
                            ) {
                                document.model.selectTrack(id: track.id)
                                onOpenTrack()
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .sheet(isPresented: $isPresentingCreateTrack) {
            CreateTrackSheet(document: $document, onOpenTrack: onOpenTrack)
        }
    }
}

private struct TrackMatrixCard: View {
    let track: StepSequenceTrack
    let group: TrackGroup?
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
        switch track.trackType {
        case .monoMelodic:
            return "MONO"
        case .polyMelodic:
            return "POLY"
        case .slice:
            return "SLICE"
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    TrackTypeBadge(trackType: track.trackType, accent: accent)
                    Spacer()
                    if let group {
                        Text(group.name.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.9)
                            .foregroundStyle(accent.opacity(0.9))
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)

                    Text(typeLabel)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Text(track.defaultDestination.summary)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.16) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
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
