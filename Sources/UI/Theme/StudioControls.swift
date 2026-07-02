import SwiftUI

/// The one circular icon button used across the app: system glyph in a
/// bordered circle. Sizes come from `StudioMetrics.ControlSize`.
struct StudioCircleIconButton: View {
    let systemName: String
    var size: CGFloat = StudioMetrics.ControlSize.close
    var accent: Color? = nil
    var isEnabled: Bool = true
    var help: String = ""
    var keyboardShortcut: KeyboardShortcut? = nil
    let action: () -> Void

    private var glyphSize: CGFloat {
        (size * 0.42).rounded()
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: glyphSize, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .overlay(Circle().stroke(stroke, lineWidth: StudioMetrics.borderWidth))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keyboardShortcut)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(help.isEmpty ? systemName : help)
    }

    /// Bold-flat pass: an accented button is a fully solid accent circle
    /// with a dark glyph inside; the plain state is outline-only on the
    /// ground — no in-between washes.
    private var foreground: Color {
        guard isEnabled else {
            return StudioTheme.mutedText.opacity(0.35)
        }
        return accent == nil ? StudioTheme.text : StudioTheme.background
    }

    private var fill: Color {
        guard isEnabled else {
            return Color.clear
        }
        return accent ?? Color.clear
    }

    private var stroke: Color {
        guard isEnabled else {
            return StudioTheme.border.opacity(0.45)
        }
        return accent ?? StudioTheme.border
    }
}

/// The compact 24pt square icon action shared by row/card action clusters
/// (phrase-row insert/duplicate/remove, scene-card duplicate/delete): 11pt
/// bold glyph on a subtleFill badge, muted `inheritedContent` tint when
/// disabled. Promoted from private per-surface copies — add new 24pt icon
/// actions through this control, not a fresh copy.
struct StudioIconActionButton: View {
    let systemImage: String
    var isDisabled: Bool = false
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isDisabled ? StudioTheme.mutedText.opacity(StudioOpacity.inheritedContent) : StudioTheme.text)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
        .accessibilityLabel(help.isEmpty ? systemImage : help)
    }
}

/// Vertically stacked increment/decrement buttons (the BPM stepper, layer
/// cycler, and friends). `symbols` defaults to plus/minus; pass chevrons for
/// cycling semantics.
struct StudioStepperButtons: View {
    var symbols: (up: String, down: String) = ("plus", "minus")
    var upHelp: String = "Increase"
    var downHelp: String = "Decrease"
    let onUp: () -> Void
    let onDown: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            stepButton(systemName: symbols.up, help: upHelp, action: onUp)
            stepButton(systemName: symbols.down, help: downHelp, action: onDown)
        }
    }

    private func stepButton(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 18, height: 13)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

enum StudioDrag {
    /// Shared vertical-drag sensitivity for value editing (knobs and cells):
    /// pixels of travel for a full-range sweep.
    static let fullRangeTravel: Double = 200

    /// Points of travel one line of a non-precise (classic mouse wheel)
    /// scroll delta is worth. Precise devices (trackpads) already report
    /// point deltas; wheels report lines, which would otherwise crawl.
    static let wheelLinePoints: Double = 8

    /// Normalizes a scroll-wheel delta to drag-equivalent points so wheel
    /// and drag share the single `fullRangeTravel` feel constant.
    static func scrollTravel(deltaY: Double, hasPreciseDeltas: Bool) -> Double {
        hasPreciseDeltas ? deltaY : deltaY * wheelLinePoints
    }

    /// The one vertical drag-to-value gesture all knobs share: dragging the
    /// full `fullRangeTravel` height sweeps the full range; the value clamps
    /// to the range; release commits via `onCommit`.
    static func verticalValueGesture(
        value: Binding<Double>,
        dragStart: Binding<Double?>,
        range: ClosedRange<Double>,
        onCommit: @escaping (Double) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                if dragStart.wrappedValue == nil {
                    dragStart.wrappedValue = value.wrappedValue
                }
                let delta = -drag.translation.height / fullRangeTravel
                let span = range.upperBound - range.lowerBound
                let next = (dragStart.wrappedValue ?? value.wrappedValue) + delta * span
                value.wrappedValue = min(max(next, range.lowerBound), range.upperBound)
            }
            .onEnded { _ in
                dragStart.wrappedValue = nil
                onCommit(value.wrappedValue)
            }
    }
}
