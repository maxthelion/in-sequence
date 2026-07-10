import SwiftUI

/// Pattern-slot cell: a 4×4 matrix of pills, one per pattern slot, with the
/// active slot lit by the current phrase accent. The matrix *is* the value —
/// no "P1"/"Pattern slot" caption repeating what the layer header already says
/// (ux-canon rules 1/3).
struct PatternIndexCellPreview: View {
    let layer: PhraseLayerDefinition
    let resolvedValue: PhraseCellValue
    let accent: Color
    let summary: String
    let isMixed: Bool
    let metrics: CellPreviewMetrics
    var onSelectSlot: ((Int) -> Void)?

    private let slotCount = TrackPatternBank.slotCount
    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: StudioMetrics.Spacing.hairline),
        count: 4
    )

    var body: some View {
        Group {
            if isMixed {
                // Mixed reads the same full-cell way as the boolean cells —
                // one big value word filling the cell, never an empty grid
                // with a foot label (canon Rules 2/5, design review 13).
                ZStack {
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                        .stroke(accent, lineWidth: StudioMetrics.borderWidth)

                    Text("Mixed")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)
                }
                .frame(height: metrics.valueHeight)
            } else {
                VStack(alignment: .leading, spacing: StudioMetrics.Spacing.tight) {
                    LazyVGrid(columns: columns, spacing: StudioMetrics.Spacing.hairline) {
                        ForEach(0..<slotCount, id: \.self) { index in
                            slotCell(index)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(StudioMetrics.Spacing.hairline)
                .frame(height: metrics.valueHeight)
                .background(cellFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
            }
        }
        .accessibilityElement(children: onSelectSlot == nil ? .ignore : .contain)
        .accessibilityLabel(isMixed ? "Mixed pattern slots" : "Pattern \(summary)")
    }

    var activeIndex: Int? {
        if case let .index(index) = resolvedValue.normalized(for: layer) {
            return min(max(index, 0), slotCount - 1)
        }
        return nil
    }

    private var pillHeight: CGFloat {
        // Four pill rows plus the cell padding must fit metrics.valueHeight.
        let inset = StudioMetrics.Spacing.hairline * 5
        return max(8, (metrics.valueHeight - inset) / 4)
    }

    /// Bold-flat pass: no tinted cell wash behind the matrix — the slot
    /// pills sit directly on the card (one less nesting level).
    private var cellFill: Color {
        Color.clear
    }

    /// Bold-flat pass: the active slot is a fully solid surface-accent block;
    /// inactive slots are outline-only on the ground.
    func slotFill(for index: Int) -> Color {
        guard let activeIndex, !isMixed, index == activeIndex else {
            return Color.clear
        }
        return accent
    }

    func slotStroke(for index: Int) -> Color {
        guard let activeIndex, !isMixed else {
            return StudioTheme.border.opacity(StudioOpacity.softStroke)
        }
        return index == activeIndex
            ? accent
            : StudioTheme.border.opacity(StudioOpacity.softStroke)
    }

    @ViewBuilder
    private func slotCell(_ index: Int) -> some View {
        let label = slotCellLabel(index)
        if let onSelectSlot {
            Button {
                onSelectSlot(index)
            } label: {
                label
                    .frame(maxWidth: .infinity)
                    .frame(height: pillHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: pillHeight)
            .contentShape(Rectangle())
            .help("P\(index + 1)")
            .accessibilityLabel("Pattern slot \(index + 1)")
            .accessibilityIdentifier("phrase-pattern-slot-\(index + 1)")
        } else {
            label
                .frame(maxWidth: .infinity)
                .frame(height: pillHeight)
        }
    }

    private func slotCellLabel(_ index: Int) -> some View {
        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
            .fill(slotFill(for: index))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                    .stroke(slotStroke(for: index), lineWidth: StudioMetrics.borderWidth)
            )
    }
}
