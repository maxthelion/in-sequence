import SwiftUI

struct MixerView: View {
    @Binding var document: SeqAIDocument

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(document.model.tracks.enumerated()), id: \.element.id) { index, track in
                    MixerChannelStrip(
                        track: $document.model.tracks[index],
                        isSelected: track.id == document.model.selectedTrackID,
                        onSelect: {
                            document.model.selectTrack(id: track.id)
                        }
                    )
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MixerChannelStrip: View {
    @Binding var track: StepSequenceTrack
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.headline)
                    Text(track.output.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Text("Selected")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.12))

                        RoundedRectangle(cornerRadius: 12)
                            .fill(track.mix.isMuted ? Color.secondary.opacity(0.3) : Color.accentColor)
                            .frame(height: max(10, proxy.size.height * track.mix.clampedLevel))
                    }
                }
                .frame(width: 28, height: 140)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Level")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((track.mix.clampedLevel * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $track.mix.level, in: 0...1)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Pan")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(panLabel)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $track.mix.pan, in: -1...1)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(track.mix.isMuted ? "Unmute" : "Mute") {
                    track.mix.isMuted.toggle()
                }
                .buttonStyle(.bordered)

                Button("Edit", action: onSelect)
                    .buttonStyle(.borderedProminent)
            }

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Label("\(track.activeStepCount) active steps", systemImage: "square.grid.2x2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(track.pitches.count) pitches", systemImage: "music.note")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(width: 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: isSelected ? 2 : 1)
        )
    }

    private var panLabel: String {
        switch track.mix.clampedPan {
        case let value where value < -0.05:
            return "L\(Int(abs(value) * 100))"
        case let value where value > 0.05:
            return "R\(Int(value * 100))"
        default:
            return "C"
        }
    }
}

#Preview {
    MixerPreview()
}

private struct MixerPreview: View {
    @State private var document = SeqAIDocument()

    var body: some View {
        MixerView(document: $document)
    }
}
