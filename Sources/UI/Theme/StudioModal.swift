import SwiftUI

/// Shared chrome for modal sheets. Every sheet gets the same dark stage
/// background (no system white bleed at the sheet corners), the same title
/// row, and a single ✕ close affordance in the top-right corner.
struct StudioModal<Content: View, HeaderAccessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var accent: Color = StudioTheme.transportAccent
    var showsTitleRule = true
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

                    if showsTitleRule {
                        Rectangle()
                            .fill(accent)
                            .frame(width: 36, height: 2)
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }

            Spacer(minLength: 12)

            // Optional title-bar accessory (e.g. a Normalize button) sits to the
            // left of the close affordance.
            headerAccessory

            StudioModalCloseButton(action: onClose)
        }
    }
}

extension StudioModal where HeaderAccessory == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        accent: Color = StudioTheme.transportAccent,
        showsTitleRule: Bool = true,
        minWidth: CGFloat = 480,
        minHeight: CGFloat? = nil,
        onClose: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            accent: accent,
            showsTitleRule: showsTitleRule,
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
