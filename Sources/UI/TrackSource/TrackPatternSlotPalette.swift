import SwiftUI

struct TrackPatternSlotPalette: View {
    @Binding var selectedSlot: Int
    let occupiedSlots: Set<Int>

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slotIndex in
                Button {
                    selectedSlot = slotIndex
                } label: {
                    HStack(spacing: 6) {
                        Text("\(slotIndex + 1)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(StudioTheme.text)

                        Circle()
                            .fill(indicatorFill(for: slotIndex))
                            .frame(width: 6, height: 6)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(backgroundFill(for: slotIndex))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(borderColor(for: slotIndex), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func backgroundFill(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success.opacity(0.2)
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.08)
        }
        return Color.white.opacity(0.03)
    }

    private func borderColor(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success.opacity(0.7)
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.28)
        }
        return StudioTheme.border
    }

    private func indicatorFill(for slotIndex: Int) -> Color {
        if selectedSlot == slotIndex {
            return StudioTheme.success
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.6)
        }
        return Color.white.opacity(0.08)
    }
}
