import CoreGraphics

/// Alpha constants for non-structural opacity and for `StudioTheme` to
/// precompose opaque neutral fill tokens. Call sites must not use these to
/// draw grey fills directly; use `StudioTheme.subtleFill`,
/// `borderSubtleFill`, and the other solid fill roles instead.
enum StudioOpacity {
    /// Theme input for the single fill step a control may take above the
    /// ground. `StudioTheme.subtleFill` is the call-site token.
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
