import CoreGraphics

/// Flat-variant values: fills read as solid colour blocks and strokes as
/// crisp visible lines, instead of low-opacity washes layered over each
/// other. Backgrounds are opaque, so a single tinted fill still composites
/// to one flat colour.
enum StudioOpacity {
    static let subtleFill: CGFloat = 0.07
    static let mutedFill: CGFloat = 0.20
    static let softFill: CGFloat = 0.24
    static let hoverFill: CGFloat = 0.26
    static let selectedFill: CGFloat = 0.32
    static let accentFill: CGFloat = 1.0

    /// Content opacity for cells that inherit a shared/default value instead
    /// of holding their own (the muted "variant of the parent").
    static let inheritedContent: CGFloat = 0.45

    static let borderSubtle: CGFloat = 0.14
    static let borderFaint: CGFloat = 0.18
    static let faintStroke: CGFloat = 0.25
    static let accentStroke: CGFloat = 0.45
    static let softStroke: CGFloat = 0.35
    static let subtleStroke: CGFloat = 0.40
    static let mediumStroke: CGFloat = 0.70
    static let ghostStroke: CGFloat = 0.80
}
