import AppKit
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

    struct TargetMode: Equatable {
        let selectedSlots: Set<Int>
        let isPrompting: Bool
        let accent: Color
    }

    @Binding var selectedSlot: Int
    let occupiedSlots: Set<Int>
    let bypassState: BypassState
    let onBypassToggle: (Int) -> Void
    var playingSlot: Int?
    var onPlayingSlotSelect: (Int) -> Void = { _ in }
    var accent: Color = StudioTheme.transportAccent
    var destinationMode: DestinationMode?
    var onDestinationSelect: (Int) -> Void = { _ in }
    var targetMode: TargetMode?
    var onTargetSelect: (Int, Bool) -> Void = { _, _ in }

    @State private var interactionPulse = false

    init(
        selectedSlot: Binding<Int>,
        occupiedSlots: Set<Int>,
        bypassState: BypassState,
        onBypassToggle: @escaping (Int) -> Void,
        playingSlot: Int? = nil,
        onPlayingSlotSelect: @escaping (Int) -> Void = { _ in },
        accent: Color = StudioTheme.transportAccent,
        destinationMode: DestinationMode? = nil,
        onDestinationSelect: @escaping (Int) -> Void = { _ in },
        targetMode: TargetMode? = nil,
        onTargetSelect: @escaping (Int, Bool) -> Void = { _, _ in }
    ) {
        self._selectedSlot = selectedSlot
        self.occupiedSlots = occupiedSlots
        self.bypassState = bypassState
        self.onBypassToggle = onBypassToggle
        self.playingSlot = playingSlot
        self.onPlayingSlotSelect = onPlayingSlotSelect
        self.accent = accent
        self.destinationMode = destinationMode
        self.onDestinationSelect = onDestinationSelect
        self.targetMode = targetMode
        self.onTargetSelect = onTargetSelect
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slotIndex in
                slotButton(at: slotIndex)
            }
        }
        .onAppear {
            interactionPulse = shouldPulse
        }
        .onChange(of: shouldPulse) { _, isActive in
            interactionPulse = isActive
        }
        .animation(
            shouldPulse ? .easeInOut(duration: 0.75).repeatForever(autoreverses: true) : nil,
            value: interactionPulse
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
                    radius: interactionPulse ? 9 : 2,
                    x: 0,
                    y: 0
                )
                .overlay(alignment: .bottom) {
                    if playingSlot == slotIndex && destinationMode == nil {
                        Capsule()
                            .fill(accent)
                            .frame(height: 3)
                            .padding(.horizontal, 10)
                            .offset(y: 6)
                    }
                }
            }
            .buttonStyle(.plain)
            .background {
                TrackPatternSlotRightClickProbe { additive in
                    guard destinationMode == nil else { return }
                    if targetMode != nil {
                        onTargetSelect(slotIndex, additive)
                    } else {
                        onPlayingSlotSelect(slotIndex)
                    }
                }
            }
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
        if targetMode?.selectedSlots.contains(slotIndex) == true {
            return "Slot \(slotNumber), template target"
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
                return destinationMode.accent
            }
            return StudioTheme.subtleFill
        }
        if selectedSlot == slotIndex {
            return accent
        }
        return StudioTheme.subtleFill
    }

    private func borderColor(for slotIndex: Int, isBypassed: Bool) -> Color {
        if let destinationMode {
            if destinationMode.pendingReplaceSlot == slotIndex {
                return destinationMode.accent
            }
            return destinationMode.accent.opacity(interactionPulse ? 0.9 : 0.45)
        }
        if let targetMode {
            if targetMode.selectedSlots.contains(slotIndex) {
                return StudioTheme.text
            }
            if targetMode.isPrompting {
                return interactionPulse ? targetMode.accent : StudioTheme.text
            }
        }
        if isBypassed {
            return selectedSlot == slotIndex
                ? accent
                : accent.opacity(0.4)
        }
        if selectedSlot == slotIndex {
            return accent
        }
        if occupiedSlots.contains(slotIndex) {
            return accent.opacity(StudioOpacity.subtleStroke)
        }
        return StudioTheme.border
    }

    private func bypassBadgeFill(_ isBypassed: Bool) -> Color {
        isBypassed ? StudioTheme.neutral : accent
    }

    private func borderWidth(for slotIndex: Int) -> CGFloat {
        if destinationMode?.pendingReplaceSlot == slotIndex
            || targetMode?.selectedSlots.contains(slotIndex) == true {
            return StudioMetrics.emphasisBorderWidth
        }
        return StudioMetrics.borderWidth
    }

    private func destinationShadowColor(for slotIndex: Int) -> Color {
        if let destinationMode {
            if destinationMode.pendingReplaceSlot == slotIndex {
                return destinationMode.accent.opacity(interactionPulse ? 0.38 : 0.12)
            }
            return destinationMode.accent.opacity(interactionPulse ? 0.32 : 0.08)
        }
        if let targetMode, targetMode.isPrompting {
            return targetMode.accent.opacity(interactionPulse ? 0.32 : 0.08)
        }
        return Color.clear
    }

    private var shouldPulse: Bool {
        destinationMode != nil || targetMode?.isPrompting == true
    }
}

private struct TrackPatternSlotRightClickProbe: NSViewRepresentable {
    let action: (Bool) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RightClickView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? RightClickView else { return }
        view.action = action
    }

    final class RightClickView: NSView {
        var action: ((Bool) -> Void)?

        override func mouseDown(with event: NSEvent) {
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                action?(event.modifierFlags.contains(.shift))
            } else {
                super.mouseDown(with: event)
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            action?(event.modifierFlags.contains(.shift))
        }
    }
}
