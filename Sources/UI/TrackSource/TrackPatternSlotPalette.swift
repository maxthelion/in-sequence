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
        let isBypassed: Bool = {
            if case .applicable(let bypassed) = bypassState { return bypassed.contains(slotIndex) }
            return false
        }()
        let bypassApplicable: Bool = {
            if case .applicable = bypassState { return true }
            return false
        }()

        ZStack(alignment: .topTrailing) {
            Button {
                selectedSlot = slotIndex
            } label: {
                HStack(spacing: 6) {
                    Text("\(slotIndex + 1)")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)

                    Circle()
                        .fill(indicatorFill(for: slotIndex, isBypassed: isBypassed))
                        .frame(width: 6, height: 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .fill(backgroundFill(for: slotIndex, isBypassed: isBypassed))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(borderColor(for: slotIndex, isBypassed: isBypassed), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                bypassApplicable
                    ? (isBypassed ? "Slot \(slotIndex + 1), clip source" : "Slot \(slotIndex + 1), generator source")
                    : "Slot \(slotIndex + 1)"
            )

            if bypassApplicable {
                Button {
                    onBypassToggle(slotIndex)
                } label: {
                    Text(isBypassed ? "C" : "G")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 14, height: 14)
                        .background(bypassBadgeFill(isBypassed), in: Circle())
                        .overlay(Circle().stroke(StudioTheme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: 4)
                .accessibilityLabel(isBypassed ? "Switch slot \(slotIndex + 1) to generator source" : "Switch slot \(slotIndex + 1) to clip source")
            }
        }
    }

    private func backgroundFill(for slotIndex: Int, isBypassed: Bool) -> Color {
        if isBypassed {
            return selectedSlot == slotIndex
                ? StudioTheme.violet.opacity(StudioOpacity.softStroke)
                : StudioTheme.violet.opacity(StudioOpacity.mutedFill)
        }
        if selectedSlot == slotIndex {
            return StudioTheme.success.opacity(StudioOpacity.softStroke)
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(StudioOpacity.borderFaint)
        }
        return Color.white.opacity(StudioOpacity.subtleFill)
    }

    private func borderColor(for slotIndex: Int, isBypassed: Bool) -> Color {
        if isBypassed {
            return selectedSlot == slotIndex
                ? StudioTheme.violet.opacity(0.7)
                : StudioTheme.violet.opacity(0.4)
        }
        if selectedSlot == slotIndex {
            return StudioTheme.success.opacity(0.7)
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(StudioOpacity.subtleStroke)
        }
        return StudioTheme.border
    }

    private func indicatorFill(for slotIndex: Int, isBypassed: Bool) -> Color {
        if isBypassed {
            return selectedSlot == slotIndex
                ? StudioTheme.violet
                : StudioTheme.violet.opacity(0.6)
        }
        if selectedSlot == slotIndex {
            return StudioTheme.success
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(0.6)
        }
        return Color.white.opacity(StudioOpacity.borderFaint)
    }

    private func bypassBadgeFill(_ isBypassed: Bool) -> Color {
        isBypassed ? StudioTheme.violet.opacity(StudioOpacity.accentFill) : StudioTheme.cyan.opacity(StudioOpacity.accentFill)
    }
}
