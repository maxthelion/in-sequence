import SwiftUI

struct MixerView: View {
    @Binding var document: SeqAIDocument
    var onEditTrack: ((UUID) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(document.model.tracks.enumerated()), id: \.element.id) { index, track in
                    MixerChannelStrip(
                        track: $document.model.tracks[index],
                        isSelected: track.id == document.model.selectedTrackID,
                        onSelect: {
                            document.model.selectTrack(id: track.id)
                            onEditTrack?(track.id)
                        }
                    )
                }
            }
            .padding(4)
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
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                    Text(track.output.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                if isSelected {
                    Text("Selected")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(StudioTheme.cyan.opacity(0.15), in: Capsule())
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                GeometryReader { proxy in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.05))

                        RoundedRectangle(cornerRadius: 12)
                            .fill(track.mix.isMuted ? Color.white.opacity(0.18) : StudioTheme.cyan)
                            .frame(height: max(10, proxy.size.height * track.mix.clampedLevel))
                    }
                }
                .frame(width: 28, height: 140)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Level")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(StudioTheme.mutedText)
                            Spacer()
                            Text("\(Int((track.mix.clampedLevel * 100).rounded()))%")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(StudioTheme.text)
                        }

                        Slider(value: $track.mix.level, in: 0...1)
                            .tint(StudioTheme.cyan)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Pan")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(StudioTheme.mutedText)
                            Spacer()
                            Text(panLabel)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(StudioTheme.text)
                        }

                        Slider(value: $track.mix.pan, in: -1...1)
                            .tint(StudioTheme.violet)
                    }
                }
            }

            HStack(spacing: 8) {
                Button(track.mix.isMuted ? "Unmute" : "Mute") {
                    track.mix.isMuted.toggle()
                }
                .buttonStyle(.borderedProminent)
                .tint(track.mix.isMuted ? StudioTheme.amber : StudioTheme.chrome)

                Button("Edit", action: onSelect)
                    .buttonStyle(.borderedProminent)
                    .tint(StudioTheme.cyan)
            }

            Rectangle()
                .fill(StudioTheme.border)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 4) {
                Label("\(track.activeStepCount) active steps", systemImage: "square.grid.2x2")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
                Label("\(track.pitches.count) pitches", systemImage: "music.note")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .padding(16)
        .frame(width: 240, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(StudioTheme.panelFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(isSelected ? StudioTheme.cyan : StudioTheme.border, lineWidth: isSelected ? 2 : 1)
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
