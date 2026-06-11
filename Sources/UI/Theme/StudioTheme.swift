import SwiftUI

enum StudioTheme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let chrome = Color(red: 0.10, green: 0.11, blue: 0.13)
    static let panelTop = Color(red: 0.17, green: 0.18, blue: 0.21)
    static let panelBottom = Color(red: 0.11, green: 0.12, blue: 0.15)
    static let border = Color.white.opacity(StudioOpacity.borderFaint)
    static let text = Color(red: 0.93, green: 0.94, blue: 0.96)
    static let mutedText = Color(red: 0.61, green: 0.64, blue: 0.70)
    static let cyan = Color(red: 0.00, green: 0.80, blue: 1.00)
    static let amber = Color(red: 1.00, green: 0.53, blue: 0.22)
    static let violet = Color(red: 0.56, green: 0.48, blue: 1.00)
    static let success = Color(red: 0.47, green: 0.91, blue: 0.63)

    /// Stable identity colours for the 16 pattern slots (P1–P16): the same
    /// slot reads as the same hue on every surface, so colour alone can say
    /// which pattern is active.
    static let patternPalette: [Color] = (0..<TrackPatternBank.slotCount).map { index in
        Color(
            hue: Double(index) / Double(TrackPatternBank.slotCount),
            saturation: 0.62,
            brightness: 0.88
        )
    }

    static func patternColor(_ index: Int) -> Color {
        let count = patternPalette.count
        return patternPalette[((index % count) + count) % count]
    }

    static let panelFill = LinearGradient(
        colors: [panelTop, panelBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let stageFill = LinearGradient(
        colors: [
            Color(red: 0.08, green: 0.09, blue: 0.11),
            Color(red: 0.05, green: 0.06, blue: 0.08)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
}
