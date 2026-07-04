import SwiftUI

struct TrackPatternSlotPalette: View {
    enum BypassState: Equatable {
        case notApplicable
        case applicable(bypassed: Set<Int>)
    }

    struct DestinationMode: Equatable {
        let pendingReplaceSlot: Int?
        let accent: Color
    }

    @Binding var selectedSlot: Int
    let occupiedSlots: Set<Int>
    let bypassState: BypassState
    let onBypassToggle: (Int) -> Void
    var destinationMode: DestinationMode?
    var onDestinationSelect: (Int) -> Void = { _ in }

    @State private var destinationPulse = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slotIndex in
                slotButton(at: slotIndex)
            }
        }
        .onAppear {
            destinationPulse = destinationMode != nil
        }
        .onChange(of: destinationMode != nil) { _, isActive in
            destinationPulse = isActive
        }
        .animation(
            destinationMode == nil ? nil : .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
            value: destinationPulse
        )
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
                if destinationMode != nil {
                    onDestinationSelect(slotIndex)
                } else {
                    selectedSlot = slotIndex
                }
            } label: {
                Text("\(slotIndex + 1)")
                    .studioText(.labelBold)
                    .foregroundStyle(hasSolidFill(for: slotIndex, isBypassed: isBypassed) ? StudioTheme.background : StudioTheme.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .fill(backgroundFill(for: slotIndex, isBypassed: isBypassed))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(borderColor(for: slotIndex, isBypassed: isBypassed), lineWidth: borderWidth(for: slotIndex))
                )
                .shadow(
                    color: destinationShadowColor(for: slotIndex),
                    radius: destinationPulse ? 9 : 2,
                    x: 0,
                    y: 0
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(slotAccessibilityLabel(slotIndex: slotIndex, isBypassed: isBypassed, bypassApplicable: bypassApplicable))

            if bypassApplicable && destinationMode == nil {
                Button {
                    onBypassToggle(slotIndex)
                } label: {
                    Text(isBypassed ? "C" : "G")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(StudioTheme.background)
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

    private func slotAccessibilityLabel(slotIndex: Int, isBypassed: Bool, bypassApplicable: Bool) -> String {
        let slotNumber = slotIndex + 1
        if destinationMode != nil {
            return "Save capture to slot \(slotNumber)"
        }
        if bypassApplicable {
            return isBypassed
                ? "Slot \(slotNumber), clip source"
                : "Slot \(slotNumber), generator source"
        }
        return "Slot \(slotNumber)"
    }

    /// Colour identifies, it never floods (ux-canon rule 12): a slot pad is
    /// either fully solid accent (selected/pending) or neutral with an accent
    /// outline — never an extra status dot or translucent accent wash.
    private func hasSolidFill(for slotIndex: Int, isBypassed: Bool) -> Bool {
        if let destinationMode {
            return destinationMode.pendingReplaceSlot == slotIndex
        }
        return selectedSlot == slotIndex
    }

    private func backgroundFill(for slotIndex: Int, isBypassed: Bool) -> Color {
        if let destinationMode {
            if destinationMode.pendingReplaceSlot == slotIndex {
                return StudioTheme.amber
            }
            return Color.white.opacity(StudioOpacity.subtleFill)
        }
        if selectedSlot == slotIndex {
            return isBypassed ? StudioTheme.violet : StudioTheme.success
        }
        return Color.white.opacity(StudioOpacity.subtleFill)
    }

    private func borderColor(for slotIndex: Int, isBypassed: Bool) -> Color {
        if let destinationMode {
            if destinationMode.pendingReplaceSlot == slotIndex {
                return StudioTheme.amber
            }
            return destinationMode.accent.opacity(destinationPulse ? 0.9 : 0.45)
        }
        if isBypassed {
            return selectedSlot == slotIndex
                ? StudioTheme.violet
                : StudioTheme.violet.opacity(0.4)
        }
        if selectedSlot == slotIndex {
            return StudioTheme.success
        }
        if occupiedSlots.contains(slotIndex) {
            return StudioTheme.success.opacity(StudioOpacity.subtleStroke)
        }
        return StudioTheme.border
    }

    private func bypassBadgeFill(_ isBypassed: Bool) -> Color {
        isBypassed ? StudioTheme.violet : StudioTheme.cyan
    }

    private func borderWidth(for slotIndex: Int) -> CGFloat {
        destinationMode?.pendingReplaceSlot == slotIndex ? 2 : 1
    }

    private func destinationShadowColor(for slotIndex: Int) -> Color {
        guard let destinationMode else {
            return Color.clear
        }
        if destinationMode.pendingReplaceSlot == slotIndex {
            return StudioTheme.amber.opacity(destinationPulse ? 0.38 : 0.12)
        }
        return destinationMode.accent.opacity(destinationPulse ? 0.32 : 0.08)
    }
}
