import CoreGraphics

/// Bold-flat values: on the single near-black ground, fills are either the
/// one allowed step above ground (`subtleFill`), a clearly-saturated state
/// tint, or fully solid (`accentFill`); strokes read as drawn lines, not
/// faint washes. Backgrounds are opaque, so a single tinted fill still
/// composites to one flat colour.
enum StudioOpacity {
    /// The single fill step a control may take above the ground; outline-only
    /// (no fill) is the preferred idiom for inactive cells/pads/steps.
    static let subtleFill: CGFloat = 0.05
    static let mutedFill: CGFloat = 0.30
    static let softFill: CGFloat = 0.35
    static let hoverFill: CGFloat = 0.38
    static let selectedFill: CGFloat = 0.50
    static let accentFill: CGFloat = 1.0

    /// Content opacity for cells that inherit a shared/default value instead
    /// of holding their own (the muted "variant of the parent").
    static let inheritedContent: CGFloat = 0.45

    static let borderSubtle: CGFloat = 0.30
    static let borderFaint: CGFloat = 0.35
    static let faintStroke: CGFloat = 0.45
    static let accentStroke: CGFloat = 0.70
    static let softStroke: CGFloat = 0.55
    static let subtleStroke: CGFloat = 0.60
    static let mediumStroke: CGFloat = 0.85
    static let ghostStroke: CGFloat = 0.95
}
