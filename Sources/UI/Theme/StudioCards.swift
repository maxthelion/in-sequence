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
                    .stroke(stroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .help(isEnabled ? "" : disabledHelp)
    }

    private var fill: Color {
        accent.map { $0.opacity(StudioOpacity.mutedFill) } ?? Color.white.opacity(StudioOpacity.subtleFill)
    }

    private var stroke: Color {
        accent.map { $0.opacity(0.35) } ?? StudioTheme.border
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
                    .foregroundStyle(accent)
                    .frame(width: StudioMetrics.ControlSize.large, height: StudioMetrics.ControlSize.large)
                    .background(accent.opacity(StudioOpacity.selectedFill), in: Circle())

                Text(label)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(StudioMetrics.Spacing.comfortable)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.hoverFill), style: StrokeStyle(lineWidth: 1, dash: Self.dashPattern))
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help.isEmpty ? label : help)
        .accessibilityLabel(help.isEmpty ? label : help)
    }
}
