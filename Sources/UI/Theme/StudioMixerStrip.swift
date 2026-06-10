import SwiftUI

/// Shared geometry for every vertical column in the mixer so identical
/// elements align row-for-row across track, send-return, bus, and master
/// columns.
enum StudioMixerStripMetrics {
    /// One narrow width for all ordinary strips.
    static let stripWidth: CGFloat = 142
    /// The master column keeps extra room for its meter scale.
    static let masterWidth: CGFloat = 190

    /// Fixed slot heights. A strip type that has nothing for a slot renders
    /// an empty slot of the same height, keeping neighbours aligned.
    static let headerHeight: CGFloat = 38
    static let processingHeight: CGFloat = 128
    static let levelsHeight: CGFloat = 196
    static let actionsHeight: CGFloat = 30
    static let footerHeight: CGFloat = 34

    static let faderSize = CGSize(width: 36, height: 150)
}

/// Slot scaffold for a mixer column: header / processing (sends, inserts,
/// FX) / levels (fader + pan) / actions (mute, solo, edit) / footer
/// (routing). All slots are fixed-height so a row of mixed strip types reads
/// as one aligned grid.
struct StudioMixerStrip<Header: View, Processing: View, Levels: View, Actions: View, Footer: View>: View {
    var width: CGFloat = StudioMixerStripMetrics.stripWidth
    var accent: Color = StudioTheme.cyan
    var isHighlighted = false
    var highlightAccent: Color? = nil
    var dimsContent = false

    @ViewBuilder var header: Header
    @ViewBuilder var processing: Processing
    @ViewBuilder var levels: Levels
    @ViewBuilder var actions: Actions
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            slot(header, height: StudioMixerStripMetrics.headerHeight)
            slot(processing, height: StudioMixerStripMetrics.processingHeight)
            slot(levels, height: StudioMixerStripMetrics.levelsHeight)
            slot(actions, height: StudioMixerStripMetrics.actionsHeight)
            slot(footer, height: StudioMixerStripMetrics.footerHeight)
        }
        .padding(StudioMetrics.Spacing.comfortable)
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
}
