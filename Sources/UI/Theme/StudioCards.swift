import SwiftUI

/// Bordered card listing one choice: bold title, optional muted detail, whole
/// card tappable. Used by destination pickers, track creation, generator
/// pickers. Leave `detail` empty when the surrounding header already states
/// the shared context (one fact, one place).
struct StudioOptionButton: View {
    let title: String
    var detail: String = ""
    /// The card's outline accent. REQUIRED so a missing surface accent can
    /// never silently fall back to grey: pass the surface accent when the
    /// card carries state (e.g. the currently-selected choice), or an
    /// explicit `nil` for a deliberately neutral action card in a pick list.
    let accent: Color?
    var minHeight: CGFloat? = nil
    var titleFontSize: CGFloat = 15
    var horizontalAlignment: HorizontalAlignment = .leading
    var contentAlignment: Alignment = .topLeading
    var centersText: Bool = false
    var isEnabled: Bool = true
    var disabledHelp: String = ""
    /// Tooltip while enabled (`disabledHelp` covers the disabled state). Use
    /// this for any instruction that would otherwise become a detail line.
    var help: String = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: horizontalAlignment, spacing: 6) {
                Text(title)
                    .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                    .multilineTextAlignment(centersText ? .center : .leading)

                if !detail.isEmpty {
                    Text(detail)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: contentAlignment)
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
        .help(isEnabled ? help : disabledHelp)
    }

    /// Bold-flat pass: option cards are outline-only on the ground; an
    /// accented card draws its outline in the accent colour instead of
    /// taking a tinted wash.
    private var fill: Color {
        Color.clear
    }

    private var stroke: Color {
        // ux-canon-allow: the neutral border only appears when a call site
        // passed an EXPLICIT nil accent (accent has no default) — a
        // deliberately plain action card, never a silently-missing accent.
        accent.map { $0.opacity(StudioOpacity.mediumStroke) } ?? StudioTheme.border
    }
}

/// Icon + label row in a subtleFill rounded tile with border, used by the
/// mixer FX pickers (mixer bus, master out) to list addable inserts. The icon
/// inherits the text colour and sits in a fixed leading well.
struct StudioFXOptionRow: View {
    let title: String
    let systemImage: String
    /// Tint for the leading icon. Defaults to the row's text color (used by the
    /// mixer/master sheets); the kit add-FX sheet passes its kit accent.
    var iconColor: Color = StudioTheme.text
    /// Fixed leading-icon column width. `nil` lets the icon size naturally (the
    /// kit sheet renders without a reserved icon column).
    var iconColumnWidth: CGFloat? = 22
    /// Tile corner radius. Defaults to `.tile`; the kit sheet uses `.badge`.
    var cornerRadius: CGFloat = StudioMetrics.CornerRadius.tile
    /// Stroke color for the tile border. Defaults to the mixer/master grammar
    /// (`border` at 0.8); the kit sheet uses the full-opacity border.
    // ux-canon-allow: the neutral tile border is structural — these are
    // action rows in an add-FX pick list, not stateful chrome; the accent
    // slot on these rows is `iconColor` (the kit sheet passes its kit
    // accent there).
    var borderColor: Color = StudioTheme.border.opacity(0.8)
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: iconColumnWidth)
                Text(title)
                    .studioText(.labelBold)
                    .lineLimit(1)
                Spacer()
            }
            .foregroundStyle(StudioTheme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: StudioMetrics.borderWidth)
        )
    }
}

/// Dashed-border "add" card used at the end of grids (tracks, scenes, busses).
struct StudioAddCard: View {
    static let dashPattern: [CGFloat] = [5, 5]

    let label: String
    var accent: Color = StudioTheme.success
    var minHeight: CGFloat = 132
    var backgroundColor: Color = Color.white.opacity(StudioOpacity.subtleFill)
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
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
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
