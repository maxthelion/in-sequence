import SwiftUI

struct PolyLaneSelector: View {
    let laneCount: Int
    @Binding var selectedLane: Int
    let onAddLane: () -> Void
    let onRemoveLane: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<laneCount, id: \.self) { laneIndex in
                Button {
                    selectedLane = laneIndex
                } label: {
                    Text("Lane \(laneIndex + 1)")
                        .studioText(.eyebrowBold)
                        .foregroundStyle(selectedLane == laneIndex ? StudioTheme.background : StudioTheme.mutedText)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(selectedLane == laneIndex ? StudioTheme.violet : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedLane == laneIndex ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                        )
                }
                .buttonStyle(.plain)
            }

            StudioCircleIconButton(systemName: "plus", help: "Add lane", action: onAddLane)

            if let onRemoveLane {
                StudioCircleIconButton(systemName: "minus", help: "Remove lane", action: onRemoveLane)
            }
            Spacer(minLength: 0)
        }
    }
}
