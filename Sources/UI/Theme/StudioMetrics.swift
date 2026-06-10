import CoreGraphics

enum StudioMetrics {
    enum CornerRadius {
        static let workspace: CGFloat = 30
        static let chrome: CGFloat = 28
        static let section: CGFloat = 22
        static let panel: CGFloat = 18
        static let subPanel: CGFloat = 16
        static let tile: CGFloat = 14
        static let control: CGFloat = 12
        static let chip: CGFloat = 10
        static let badge: CGFloat = 8
        static let mini: CGFloat = 4
    }

    /// Padding scale. Stack `spacing:` literals remain accepted as
    /// micro-layout; `.padding` values should come from this scale.
    enum Spacing {
        static let hairline: CGFloat = 4
        static let tight: CGFloat = 6
        static let snug: CGFloat = 8
        static let compact: CGFloat = 10
        static let comfortable: CGFloat = 12
        static let standard: CGFloat = 14
        static let roomy: CGFloat = 16
        static let loose: CGFloat = 18
        static let section: CGFloat = 20
        static let page: CGFloat = 24
    }

    /// Square sizes for circular icon buttons and knobs.
    enum ControlSize {
        static let small: CGFloat = 24
        static let close: CGFloat = 28
        static let medium: CGFloat = 30
        static let large: CGFloat = 34
        static let knob: CGFloat = 40
    }
}
