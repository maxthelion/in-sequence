import SwiftUI

struct TrackPatternSlotPalette: View {
    enum BypassState: Equatable {
        case notApplicable
        case applicable(bypassed: Set<Int>)
    }

    @Binding var selectedSlot: Int
    let occupiedSlots: Set<Int>
    let bypassState: BypassState
    let onBypassToggle: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slotIndex in
                slotButton(at: slotIndex)
            }
        }
    }

    @ViewBuilder
    private func slotButton(at slotIndex: Int) -> some View {
        ZStack(alignment: .topTrailing) {
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

            if case .applicable(let bypassed) = bypassState {
                Button {
                    onBypassToggle(slotIndex)
                } label: {
                    Text(bypassed.contains(slotIndex) ? "C" : "G")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(bypassBadgeForeground(bypassed.contains(slotIndex)))
                        .frame(width: 14, height: 14)
                        .background(bypassBadgeFill(bypassed.contains(slotIndex)), in: Circle())
                        .overlay(Circle().stroke(StudioTheme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: 4)
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

    private func bypassBadgeFill(_ isBypassed: Bool) -> Color {
        isBypassed ? StudioTheme.violet.opacity(0.55) : StudioTheme.cyan.opacity(0.55)
    }

    private func bypassBadgeForeground(_ isBypassed: Bool) -> Color {
        StudioTheme.text
    }
}
