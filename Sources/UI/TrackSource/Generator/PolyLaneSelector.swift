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
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(selectedLane == laneIndex ? StudioTheme.text : StudioTheme.mutedText)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(selectedLane == laneIndex ? StudioTheme.violet.opacity(0.16) : Color.white.opacity(0.03), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedLane == laneIndex ? StudioTheme.violet.opacity(0.5) : StudioTheme.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Button(action: onAddLane) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .padding(8)
                    .background(Color.white.opacity(0.03), in: Circle())
            }
            .buttonStyle(.plain)

            if let onRemoveLane {
                Button(action: onRemoveLane) {
                    Image(systemName: "minus")
                        .font(.system(size: 11, weight: .bold))
                        .padding(8)
                        .background(Color.white.opacity(0.03), in: Circle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
