import SwiftUI

struct MixerView: View {
    @Binding var document: SeqAIDocument
    var onEditTrack: ((UUID) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(track.name)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                    Text(track.output.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
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

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .center, spacing: 8) {
                        VerticalLevelFader(level: $track.mix.level, isMuted: track.mix.isMuted)
                            .frame(width: 36, height: 150)

                        Text("\(Int((track.mix.clampedLevel * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(StudioTheme.text)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pan")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(StudioTheme.mutedText)

                        HStack(spacing: 8) {
                            Slider(value: $track.mix.pan, in: -1...1)
                                .tint(StudioTheme.violet)
                                .frame(width: 88)

                            Text(panLabel)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(StudioTheme.text)
                                .frame(width: 28, alignment: .trailing)
                        }
                    }
                    .padding(.bottom, 4)
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
        .frame(width: 200, alignment: .topLeading)
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

private struct VerticalLevelFader: View {
    @Binding var level: Double
    let isMuted: Bool

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let filledHeight = max(12, height * clampedLevel)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isMuted ? Color.white.opacity(0.18) : StudioTheme.cyan)
                    .frame(height: filledHeight)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 16, height: 4)
                    .offset(y: -filledHeight + 10)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let next = 1 - (value.location.y / max(height, 1))
                        level = min(max(next, 0), 1)
                    }
            )
        }
    }

    private var clampedLevel: Double {
        min(max(level, 0), 1)
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
