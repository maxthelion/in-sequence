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

func cycledValue(_ value: PhraseCellValue, for layer: PhraseLayerDefinition) -> PhraseCellValue {
    switch layer.valueType {
    case .boolean:
        if case let .bool(isOn) = value.normalized(for: layer) {
            return .bool(!isOn)
        }
        return .bool(true)
    case .patternIndex:
        if case let .index(index) = value.normalized(for: layer) {
            return .index((index + 1) % TrackPatternBank.slotCount)
        }
        return .index(0)
    case .scalar:
        let current: Double
        if case let .scalar(scalar) = value.normalized(for: layer) {
            current = scalar
        } else {
            current = layer.minValue
        }
        let step = (layer.maxValue - layer.minValue) / 4
        let next = current + step
        if next > layer.maxValue {
            return .scalar(layer.minValue)
        }
        return .scalar(next)
    }
}

func toggledBooleanValue(_ value: PhraseCellValue, for layer: PhraseLayerDefinition) -> PhraseCellValue {
    guard case let .bool(isOn) = value.normalized(for: layer) else {
        return .bool(true)
    }
    return .bool(!isOn)
}

struct ScalarValueEditor: View {
    let title: String?
    let range: ClosedRange<Double>
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            HStack(spacing: 10) {
                Slider(value: $value, in: range)
                Text(formattedValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(width: 54, alignment: .trailing)
            }
        }
    }

    private var formattedValue: String {
        if range.upperBound <= 1.01 && range.lowerBound >= 0 {
            return "\(Int((value * 100).rounded()))%"
        }
        if range.lowerBound < 0 {
            return "\(Int(value.rounded()))"
        }
        return "\(Int(value.rounded()))"
    }
}

struct PatternIndexPicker: View {
    @Binding var selectedIndex: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<TrackPatternBank.slotCount, id: \.self) { index in
                    Button {
                        selectedIndex = index
                    } label: {
                        Text("P\(index + 1)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(index == selectedIndex ? StudioTheme.violet.opacity(0.2) : Color.white.opacity(0.04), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct PhraseCurvePreview: View {
    let points: [Double]
    let range: ClosedRange<Double>
    let accent: Color

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let sampled = (0..<64).map { index in
                    PhraseCurveSampler.sample(points: points, at: index, stepCount: 64, range: range)
                }

                for (index, value) in sampled.enumerated() {
                    let x = geometry.size.width * CGFloat(Double(index) / Double(max(1, sampled.count - 1)))
                    let yRatio = (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
                    let y = geometry.size.height * CGFloat(1 - yRatio)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(accent, lineWidth: 3)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

enum PhraseCurvePreset: CaseIterable {
    case flat
    case rise
    case fall
    case swell

    var label: String {
        switch self {
        case .flat:
            return "Flat"
        case .rise:
            return "Rise"
        case .fall:
            return "Fall"
        case .swell:
            return "Swell"
        }
    }

    func points(in range: ClosedRange<Double>) -> [Double] {
        let low = range.lowerBound
        let high = range.upperBound
        let mid = (low + high) / 2

        switch self {
        case .flat:
            return [mid, mid, mid, mid]
        case .rise:
            return [low, low, mid, high]
        case .fall:
            return [high, mid, low, low]
        case .swell:
            return [low, high, high, low]
        }
    }
}

func valueLabel(_ value: PhraseCellValue, layer: PhraseLayerDefinition) -> String {
    switch value.normalized(for: layer) {
    case let .bool(isOn):
        return isOn ? "On" : "Off"
    case let .index(index):
        return "P\(index + 1)"
    case let .scalar(scalar):
        if layer.maxValue <= 1.01 && layer.minValue >= 0 {
            return "\(Int((scalar * 100).rounded()))%"
        }
        if layer.id == "transpose" {
            return "\(Int(scalar.rounded())) st"
        }
        return "\(Int(scalar.rounded()))"
    }
}

func scalarValue(for value: PhraseCellValue, layer: PhraseLayerDefinition) -> Double {
    switch value.normalized(for: layer) {
    case let .scalar(scalar):
        return scalar
    case let .index(index):
        return Double(index)
    case let .bool(isOn):
        return isOn ? layer.maxValue : layer.minValue
    }
}

func scalarRatio(_ value: Double, layer: PhraseLayerDefinition) -> Double {
    (value - layer.minValue) / max(0.0001, layer.maxValue - layer.minValue)
}

func cellSummary(_ cell: PhraseCell, layer: PhraseLayerDefinition, phrase: PhraseModel) -> String {
    switch cell {
    case .inheritDefault:
        return "Default"
    case let .single(value):
        return valueLabel(value, layer: layer)
    case let .bars(values):
        return "\(values.count) bars"
    case let .steps(values):
        return "\(values.count) steps"
    case .curve:
        return "\(phrase.lengthBars) bar curve"
    }
}
