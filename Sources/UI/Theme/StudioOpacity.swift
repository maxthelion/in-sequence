import CoreGraphics

enum StudioOpacity {
    static let subtleFill: CGFloat = 0.03
    static let mutedFill: CGFloat = 0.12
    static let softFill: CGFloat = 0.15
    static let hoverFill: CGFloat = 0.16
    static let selectedFill: CGFloat = 0.18
    static let accentFill: CGFloat = 0.55

    /// Content opacity for cells that inherit a shared/default value instead
    /// of holding their own (the muted "variant of the parent").
    static let inheritedContent: CGFloat = 0.45

    static let borderSubtle: CGFloat = 0.06
    static let borderFaint: CGFloat = 0.08
    static let faintStroke: CGFloat = 0.14
    static let accentStroke: CGFloat = 0.24
    static let softStroke: CGFloat = 0.2
    static let subtleStroke: CGFloat = 0.28
    static let mediumStroke: CGFloat = 0.45
    static let ghostStroke: CGFloat = 0.5
}
