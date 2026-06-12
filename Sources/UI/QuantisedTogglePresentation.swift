import SwiftUI

/// Shared presentation grammar for quantise-armed perform toggles
/// (perform-setup wireframes §2): an ARMED toggle reads as a dashed amber
/// outline plus the pending glyph — the shipped step-order pendingOn/Off
/// grammar — and becomes solid when it applies at the boundary.
enum QuantisedTogglePresentation {
    /// The pending glyph: the same "lands at a time boundary" mark the
    /// wireframe's armed cell carries.
    static let pendingGlyphSystemName = "timer"
    /// Dash pattern shared with the established dashed-pending strokes.
    static let pendingDashPattern: [CGFloat] = [5, 5]

    static func strokeStyle(isPending: Bool, lineWidth: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: lineWidth, dash: isPending ? pendingDashPattern : [])
    }
}

/// Fill-cell state labels for the quantised next-cycle cue (rytm-study §5:
/// cue → plays the next loop → auto-returns).
struct QuantisedFillCuePresentation: Equatable {
    let isPending: Bool
    let isCueBarActive: Bool

    /// Headline state for the fill trigger cell; nil defers to the cell's
    /// existing READY/HELD/LATCHED/ACTIVE labels.
    var stateLabel: String? {
        if isPending {
            return "CUED"
        }
        return nil
    }

    /// Secondary line naming when the cue lands / when it ends.
    var detailLabel: String? {
        if isPending {
            return "NEXT BAR"
        }
        if isCueBarActive {
            return "THIS BAR"
        }
        return nil
    }

    var usesDashedStroke: Bool {
        isPending
    }
}
