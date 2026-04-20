import Foundation

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
