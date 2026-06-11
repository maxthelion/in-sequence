import SwiftUI

enum StudioTheme {
    /// Bold-flat pass: ONE near-black ground (~#0d0d10). Window, top bar,
    /// stage, and panels all sit on this single value; grouping reads from
    /// spacing, dividers, and outlines — never from another grey rectangle.
    static let background = Color(red: 0.051, green: 0.051, blue: 0.063)
    static let chrome = background

    /// Panels are pure grouping: same ground as the stage. A card/control may
    /// take at most one fill step above this (see `StudioOpacity.subtleFill`),
    /// or no fill at all — outline only.
    static let panel = background

    /// Solid darker well for inset tracks/lanes (step wells, fader tracks,
    /// segmented control troughs); reads as a cut below the single ground.
    static let inset = Color(red: 0.024, green: 0.024, blue: 0.032)

    /// Drawn-line outline (~#62626c): clearly visible mid-grey on the
    /// near-black ground, the default idiom for inactive controls.
    static let border = Color(red: 0.384, green: 0.384, blue: 0.424)

    static let text = Color(red: 0.91, green: 0.91, blue: 0.925)
    static let mutedText = Color(red: 0.604, green: 0.604, blue: 0.643)
    static let cyan = Color(red: 0.00, green: 0.80, blue: 1.00)
    static let amber = Color(red: 1.00, green: 0.53, blue: 0.22)
    static let violet = Color(red: 0.63, green: 0.53, blue: 1.00)
    static let success = Color(red: 0.30, green: 0.92, blue: 0.52)
    static let danger = Color(red: 1.00, green: 0.32, blue: 0.34)

    /// Stable identity colours for the 16 pattern slots (P1–P16): the same
    /// slot reads as the same hue on every surface, so colour alone can say
    /// which pattern is active.
    static let patternPalette: [Color] = (0..<TrackPatternBank.slotCount).map { index in
        Color(
            hue: Double(index) / Double(TrackPatternBank.slotCount),
            saturation: 0.78,
            brightness: 0.95
        )
    }

    static func patternColor(_ index: Int) -> Color {
        let count = patternPalette.count
        return patternPalette[((index % count) + count) % count]
    }

    /// Bold-flat pass: panels and the stage share the single ground.
    static let panelFill = panel
    static let stageFill = background
}
