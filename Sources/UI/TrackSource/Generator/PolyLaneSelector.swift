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
                        .foregroundStyle(selectedLane == laneIndex ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(selectedLane == laneIndex ? StudioTheme.violet.opacity(StudioOpacity.hoverFill) : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedLane == laneIndex ? StudioTheme.violet.opacity(StudioOpacity.ghostStroke) : StudioTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Button(action: onAddLane) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .padding(8)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
            }
            .buttonStyle(.plain)

            if let onRemoveLane {
                Button(action: onRemoveLane) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .padding(8)
                        .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
