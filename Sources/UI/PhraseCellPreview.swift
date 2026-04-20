import SwiftUI

struct PhraseCellPreview: View {
    enum Style {
        case matrix
        case live

        var booleanHeight: CGFloat {
            switch self {
            case .matrix:
                return 72
            case .live:
                return 92
            }
        }

        var valueHeight: CGFloat {
            switch self {
            case .matrix:
                return 84
            case .live:
                return 98
            }
        }

        var booleanAccentOpacity: Double {
            switch self {
            case .matrix:
                return 0.65
            case .live:
                return 0.72
            }
        }

        var muteOnOpacity: Double {
            switch self {
            case .matrix:
                return 0.7
            case .live:
                return 0.75
            }
        }
    }

    let layer: PhraseLayerDefinition
    let cell: PhraseCell
    let resolvedValue: PhraseCellValue
    let accent: Color
    let summary: String
    let isMixed: Bool
    let style: Style

    init(
        layer: PhraseLayerDefinition,
        cell: PhraseCell,
        resolvedValue: PhraseCellValue,
        accent: Color,
        summary: String,
        isMixed: Bool = false,
        style: Style = .matrix
    ) {
        self.layer = layer
        self.cell = cell
        self.resolvedValue = resolvedValue
        self.accent = accent
        self.summary = summary
        self.isMixed = isMixed
        self.style = style
    }

    var body: some View {
        switch layer.valueType {
        case .boolean:
            booleanPreview
        case .scalar:
            scalarPreview(fillRatio: scalarRatio(scalarValue(for: resolvedValue, layer: layer), layer: layer))
        case .patternIndex:
            scalarPreview(fillRatio: 1.0)
        }
    }

    private var booleanState: Bool {
        if case let .bool(isOn) = resolvedValue.normalized(for: layer) {
            return isOn
        }
        return false
    }

    private var booleanLabel: String {
        if isMixed {
            return "Mixed"
        }
        if layer.id == "mute" {
            return booleanState ? "Muted" : "Live"
        }
        return booleanState ? "On" : "Off"
    }

    private var booleanFill: Color {
        if layer.id == "mute" {
            return booleanState ? Color.red.opacity(style.muteOnOpacity) : StudioTheme.success.opacity(0.55)
        }
        return booleanState ? accent.opacity(style.booleanAccentOpacity) : Color.white.opacity(0.04)
    }

    private var booleanPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(booleanFill)

            Text(booleanLabel)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
        }
        .frame(height: style.booleanHeight)
    }

    private func scalarPreview(fillRatio: Double) -> some View {
        GeometryReader { geometry in
            let clampedRatio = min(max(fillRatio, 0), 1)
            let fillHeight = max(6, geometry.size.height * clampedRatio)

            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.04))

                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.8))
                    .frame(height: fillHeight)

                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(summary)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(isMixed ? "Mixed member values" : cell.editMode.label)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.text.opacity(0.85))
                        .lineLimit(1)
                }
                .padding(10)
            }
        }
        .frame(height: style.valueHeight)
    }
}
