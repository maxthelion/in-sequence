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
                .overlay(Circle().stroke(stroke, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(keyboardShortcut)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(help.isEmpty ? systemName : help)
    }

    private var foreground: Color {
        guard isEnabled else {
            return StudioTheme.mutedText.opacity(0.35)
        }
        return accent ?? StudioTheme.text
    }

    private var fill: Color {
        guard isEnabled else {
            return Color.white.opacity(0.025)
        }
        if let accent {
            return accent.opacity(StudioOpacity.selectedFill)
        }
        return Color.white.opacity(StudioOpacity.subtleFill)
    }

    private var stroke: Color {
        guard isEnabled else {
            return StudioTheme.border.opacity(0.45)
        }
        return accent.map { $0.opacity(StudioOpacity.mediumStroke) } ?? StudioTheme.border
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
                        .stroke(StudioTheme.border, lineWidth: 1)
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
}
