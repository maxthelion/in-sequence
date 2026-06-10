import SwiftUI

/// Shared chrome for modal sheets. Every sheet gets the same dark stage
/// background (no system white bleed at the sheet corners), the same title
/// row, and a single ✕ close affordance in the top-right corner.
struct StudioModal<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var accent: Color = StudioTheme.cyan
    var minWidth: CGFloat = 480
    var minHeight: CGFloat? = nil
    var onClose: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            StudioTheme.stageFill.ignoresSafeArea()

            VStack(alignment: .leading, spacing: StudioMetrics.Spacing.standard) {
                header
                content
            }
            .padding(20)
        }
        .frame(minWidth: minWidth, minHeight: minHeight)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 10) {
                    Text(title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)

                    Rectangle()
                        .fill(accent)
                        .frame(width: 36, height: 2)
                }

                if let subtitle {
                    Text(subtitle)
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            Spacer(minLength: 12)

            StudioModalCloseButton(action: onClose)
        }
    }
}

/// The one close affordance used across all modal surfaces: a circled ✕.
/// Also responds to Esc via the cancel keyboard shortcut.
struct StudioModalCloseButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: Circle())
                .overlay(Circle().stroke(StudioTheme.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Close")
        .accessibilityLabel("Close")
    }
}
