import SwiftUI

/// Shared geometry for every vertical column in the mixer so identical
/// elements align row-for-row across track, send-return, bus, and master
/// columns.
enum StudioMixerStripMetrics {
    /// One narrow width for all ordinary strips. Reduced to ~2/3 of the prior
    /// 142pt so channel strips no longer eat horizontal room (bug 134440).
    static let stripWidth: CGFloat = 96
    /// The master column keeps a little extra room for its meter scale, but
    /// no more than it needs — it was noticeably wider than the channels.
    /// Trimmed in step with the narrower channel strips.
    static let masterWidth: CGFloat = 118

    /// Fixed slot heights. A strip type that has nothing for a slot renders
    /// an empty slot of the same height, keeping neighbours aligned.
    static let headerHeight: CGFloat = 38
    static let processingHeight: CGFloat = 128
    static let levelsHeight: CGFloat = 172
    static let panHeight: CGFloat = 56
    static let actionsHeight: CGFloat = 30
    static let footerHeight: CGFloat = 34

    static let faderSize = CGSize(width: 36, height: 150)
    static let masterFaderWidth: CGFloat = 58

    static let slotSpacing: CGFloat = 10
    static let stripPadding: CGFloat = StudioMetrics.Spacing.comfortable

    /// Total rendered height of a strip — slot heights plus inter-slot
    /// spacing plus padding. Sibling tiles (Add Bus) match this so same-kind
    /// cards share dimensions (ux-canon rule 5).
    static var stripHeight: CGFloat {
        let slots = headerHeight + processingHeight + levelsHeight + panHeight + actionsHeight + footerHeight
        return slots + slotSpacing * 5 + stripPadding * 2
    }
}

/// Slot scaffold for a mixer column: header / processing (sends, inserts,
/// FX) / levels (fader + meter) / pan (side-to-side scalar) / actions
/// (mute, solo, edit) / footer (routing). All slots are fixed-height so a
/// row of mixed strip types reads as one aligned grid.
struct StudioMixerStrip<Header: View, Processing: View, Levels: View, Pan: View, Actions: View, Footer: View>: View {
    var width: CGFloat = StudioMixerStripMetrics.stripWidth
    var accent: Color = StudioTheme.cyan
    var isHighlighted = false
    var highlightAccent: Color? = nil
    var dimsContent = false

    @ViewBuilder var header: Header
    @ViewBuilder var processing: Processing
    @ViewBuilder var levels: Levels
    @ViewBuilder var pan: Pan
    @ViewBuilder var actions: Actions
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: StudioMixerStripMetrics.slotSpacing) {
            slot(header, height: StudioMixerStripMetrics.headerHeight)
            slot(processing, height: StudioMixerStripMetrics.processingHeight)
            slot(levels, height: StudioMixerStripMetrics.levelsHeight)
            slot(pan, height: StudioMixerStripMetrics.panHeight)
            slot(actions, height: StudioMixerStripMetrics.actionsHeight)
            slot(footer, height: StudioMixerStripMetrics.footerHeight)
        }
        .padding(StudioMixerStripMetrics.stripPadding)
        .frame(width: width, alignment: .topLeading)
        .background(StudioTheme.panelFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(
                    isHighlighted ? (highlightAccent ?? accent) : accent.opacity(StudioOpacity.accentStroke),
                    lineWidth: isHighlighted ? 2 : 1
                )
        )
        .opacity(dimsContent ? 0.58 : 1)
    }

    private func slot<Content: View>(_ content: Content, height: CGFloat) -> some View {
        content
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
    }
}

/// Linear gain (0…1+) rendered as a dB label — the one unit language for
/// level readouts across strips and the master column.
enum StudioLevelFormat {
    static func dBLabel(forLinear level: Double) -> String {
        guard level > 0 else { return "-inf" }
        let db = 20 * log10(level)
        if abs(db) < 0.05 { return "0 dB" }
        return String(format: "%+.1f", db)
    }

    /// Live peak readout (dBFS) for meter-only lanes like the send returns.
    static func dBFSLabel(forPeak dbFS: Double) -> String {
        guard dbFS.isFinite else { return "-inf" }
        return String(format: "%.1f", dbFS)
    }
}
