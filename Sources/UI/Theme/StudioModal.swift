import SwiftUI

/// Shared chrome for modal sheets. Every sheet gets the same dark stage
/// background (no system white bleed at the sheet corners), the same title
/// row, and a single ✕ close affordance in the top-right corner.
struct StudioModal<Content: View, HeaderAccessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var accent: Color = StudioTheme.transportAccent
    var minWidth: CGFloat = 480
    var minHeight: CGFloat? = nil
    var onClose: () -> Void
    @ViewBuilder var headerAccessory: HeaderAccessory
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            StudioTheme.stageFill.ignoresSafeArea()

            VStack(alignment: .leading, spacing: StudioMetrics.Spacing.standard) {
                header
                content
            }
            .padding(StudioMetrics.Spacing.section)
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
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .help(subtitle ?? title)
                .accessibilityHint(subtitle ?? "")

                // Keep the subtitle parameter for existing sheet call sites,
                // but modal headers intentionally render as title-only chrome;
                // contextual detail is exposed as help/accessibility instead.
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 12)

            // Optional title-bar accessory (e.g. a Normalize button) sits to the
            // left of the close affordance.
            headerAccessory
                .fixedSize()

            StudioModalCloseButton(action: onClose)
                .fixedSize()
        }
    }
}

extension StudioModal where HeaderAccessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        accent: Color = StudioTheme.transportAccent,
        minWidth: CGFloat = 480,
        minHeight: CGFloat? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            accent: accent,
            minWidth: minWidth,
            minHeight: minHeight,
            onClose: onClose,
            headerAccessory: { EmptyView() },
            content: content
        )
    }
}

/// The one close affordance used across all modal surfaces: a circled ✕.
/// Also responds to Esc via the cancel keyboard shortcut.
struct StudioModalCloseButton: View {
    var action: () -> Void

    var body: some View {
        StudioCircleIconButton(
            systemName: "xmark",
            size: StudioMetrics.ControlSize.close,
            help: "Close",
            keyboardShortcut: KeyboardShortcut(.escape, modifiers: []),
            action: action
        )
    }
}
