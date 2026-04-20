import SwiftUI

struct TrackSourceModePalette: View {
    let trackType: TrackType
    @Binding var selectedSource: TrackSourceMode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(TrackSourceMode.available(for: trackType), id: \.self) { source in
                Button {
                    selectedSource = source
                } label: {
                    Text(source.label)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedSource == source ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                        .background(fill(for: source), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(stroke(for: source), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func accent(for source: TrackSourceMode) -> Color {
        switch source {
        case .generator:
            return StudioTheme.cyan
        case .clip:
            return StudioTheme.violet
        }
    }

    private func fill(for source: TrackSourceMode) -> Color {
        selectedSource == source ? accent(for: source).opacity(0.14) : Color.white.opacity(0.03)
    }

    private func stroke(for source: TrackSourceMode) -> Color {
        selectedSource == source ? accent(for: source).opacity(0.52) : StudioTheme.border
    }
}
