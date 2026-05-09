import CoreGraphics
import Foundation

enum MasterOutputColumnPresentation: Equatable {
    case fullColumn(width: CGFloat)
    case compactStrip(width: CGFloat)

    var usesCompactOverlay: Bool {
        switch self {
        case .fullColumn: false
        case .compactStrip: true
        }
    }
}

enum MasterOutputColumnLayout {
    static let compactBreakpoint: CGFloat = 540
    static let fullColumnWidth: CGFloat = 190
    static let compactStripWidth: CGFloat = 44

    static func presentation(for workspaceWidth: CGFloat) -> MasterOutputColumnPresentation {
        workspaceWidth < compactBreakpoint
            ? .compactStrip(width: compactStripWidth)
            : .fullColumn(width: fullColumnWidth)
    }
}

enum MasterOutputClearClipControlMetrics {
    static let minWidth: CGFloat = 34
    static let minHeight: CGFloat = 22
}

enum MasterOutputGainScale {
    static let gainRange = MasterBusState.masterOutputGainRange
    static let unityPosition = position(forGain: 1)

    static func position(forGain gain: Double) -> Double {
        let normalizedGain = (clamp(gain, to: gainRange) - gainRange.lowerBound)
            / (gainRange.upperBound - gainRange.lowerBound)
        return clamp(pow(normalizedGain, 0.38), to: 0...1)
    }

    static func gain(forPosition position: Double) -> Double {
        let normalizedPosition = clamp(position, to: 0...1)
        let normalizedGain = pow(normalizedPosition, 1 / 0.38)
        let gain = gainRange.lowerBound + normalizedGain * (gainRange.upperBound - gainRange.lowerBound)
        return clamp(gain, to: gainRange)
    }

    static func dbLabel(forGain gain: Double) -> String {
        let clamped = clamp(gain, to: gainRange)
        guard clamped > 0 else { return "-inf" }
        let db = 20 * log10(clamped)
        if abs(db) < 0.05 { return "0 dB" }
        return String(format: "%+.1f dB", db)
    }
}

enum MasterMeterLevelScale {
    static let floorDBFS = -60.0
    static let ceilingDBFS = 0.0

    static func normalized(_ dbFS: Double) -> Double {
        guard dbFS.isFinite else { return 0 }
        return clamp((dbFS - floorDBFS) / (ceilingDBFS - floorDBFS), to: 0...1)
    }
}

private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
}
