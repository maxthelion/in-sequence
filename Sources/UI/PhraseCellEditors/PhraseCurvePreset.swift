import Foundation

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
