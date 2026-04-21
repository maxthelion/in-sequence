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
    }

    enum Spacing {
        static let tight: CGFloat = 6
        static let snug: CGFloat = 8
        static let standard: CGFloat = 14
        static let loose: CGFloat = 18
    }
}
