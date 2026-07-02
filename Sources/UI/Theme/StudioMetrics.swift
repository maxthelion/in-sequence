import SwiftUI

enum StudioMetrics {
    /// The one outline weight: outlines must read as drawn lines on the
    /// near-black ground, so every standard control stroke uses this.
    static let borderWidth: CGFloat = 1.5

    /// Matrix grids (track/phrase matrices, perform-layer grids, the cell
    /// editor) are a fixed 8 columns wide — the canonical "pattern" width.
    /// Build columns through `matrixColumns(...)` so the count + spacing are
    /// standardized in one place instead of repeated `count: 8` literals.
    enum Grid {
        static let matrixColumnCount = 8

        static func matrixColumns(
            spacing: CGFloat = Spacing.compact,
            minimum: CGFloat? = nil,
            maximum: CGFloat? = nil
        ) -> [GridItem] {
            let size: GridItem.Size
            switch (minimum, maximum) {
            case let (min?, max?): size = .flexible(minimum: min, maximum: max)
            case let (min?, nil): size = .flexible(minimum: min)
            default: size = .flexible()
            }
            return Array(repeating: GridItem(size, spacing: spacing), count: matrixColumnCount)
        }
    }

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

        /// Minimum effective hit-target diameter for small controls (Apple's
        /// 44pt floor). Knobs drawn smaller than this still hit-test at this
        /// size via an invisible inset-out content shape.
        static let minimumHitTarget: CGFloat = 44
    }
}
