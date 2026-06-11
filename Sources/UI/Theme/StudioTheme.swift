import SwiftUI

enum StudioTheme {
    static let background = Color(red: 0.06, green: 0.07, blue: 0.09)
    static let chrome = Color(red: 0.10, green: 0.11, blue: 0.13)

    /// Flat variant: panels are one solid value step above the stage; depth
    /// reads from colour value, not gradients, shadows, or stacked washes.
    static let panel = Color(red: 0.13, green: 0.14, blue: 0.17)

    /// Solid darker well for inset tracks/lanes (step wells, fader tracks,
    /// segmented control troughs) — replaces faint white washes.
    static let inset = Color(red: 0.045, green: 0.05, blue: 0.065)

    /// Crisp solid hairline for control outlines (no translucent white).
    static let border = Color(red: 0.27, green: 0.29, blue: 0.33)

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

    /// Flat variant: solid panel fill (was a top-leading gradient).
    static let panelFill = panel

    /// Flat variant: solid stage fill (was a vertical gradient).
    static let stageFill = Color(red: 0.07, green: 0.08, blue: 0.10)
}
