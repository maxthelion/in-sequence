import SwiftUI

/// Bordered card listing one choice: bold title, optional muted detail, whole
/// card tappable. Used by destination pickers, track creation, generator
/// pickers. Leave `detail` empty when the surrounding header already states
/// the shared context (one fact, one place).
struct StudioOptionButton: View {
    let title: String
    var detail: String = ""
    var accent: Color? = nil
    var minHeight: CGFloat? = nil
    var isEnabled: Bool = true
    var disabledHelp: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)

                if !detail.isEmpty {
                    Text(detail)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .padding(StudioMetrics.Spacing.standard)
            .background(fill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(stroke, lineWidth: StudioMetrics.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(isEnabled ? "" : disabledHelp)
    }

    /// Bold-flat pass: option cards are outline-only on the ground; an
    /// accented card draws its outline in the accent colour instead of
    /// taking a tinted wash.
    private var fill: Color {
        Color.clear
    }

    private var stroke: Color {
        accent.map { $0.opacity(StudioOpacity.mediumStroke) } ?? StudioTheme.border
    }
}

/// Icon + label row in a subtleFill rounded tile with border, used by the
/// mixer FX pickers (mixer bus, master out) to list addable inserts. The icon
/// inherits the text colour and sits in a fixed leading well.
struct StudioFXOptionRow: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 22)
                Text(title)
                    .studioText(.labelBold)
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(StudioTheme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.8), lineWidth: StudioMetrics.borderWidth)
        )
    }
}

/// Dashed-border "add" card used at the end of grids (tracks, scenes, busses).
struct StudioAddCard: View {
    static let dashPattern: [CGFloat] = [5, 5]

    let label: String
    var accent: Color = StudioTheme.success
    var minHeight: CGFloat = 132
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(StudioTheme.background)
                    .frame(width: StudioMetrics.ControlSize.large, height: StudioMetrics.ControlSize.large)
                    .background(accent, in: Circle())

                // Pass an empty label when the "+" alone is enough; the help
                // string still names the action for tooltip and accessibility.
                if !label.isEmpty {
                    Text(label)
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.text)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(StudioMetrics.Spacing.comfortable)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.hoverFill), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: Self.dashPattern))
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help.isEmpty ? label : help)
        .accessibilityLabel(help.isEmpty ? label : help)
    }
}
