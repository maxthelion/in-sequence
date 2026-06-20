import SwiftUI

// Matrix-tab content for the kit matrix: the kit-level pattern slot binding
// (the pills themselves now live in the header box), the layer selector,
// mismatch/stale/empty states, and the matrix rows list + accordion toggle.
// Split out of DrumKitMatrixView.swift as an extension.

extension DrumKitMatrixView {
    /// Kit-level 1–16 pattern slot binding. Selecting slot N applies that
    /// pattern across the whole kit (the kit supports only kit-level patterns).
    /// The pills are rendered in the header box (`headerPatternPalette`).
    func groupPatternSlotBinding(_ model: DrumKitMatrixModel) -> Binding<Int> {
        Binding(
            get: { model.groupSelectedSlotIndex ?? -1 },
            set: { newValue in
                guard (0..<TrackPatternBank.slotCount).contains(newValue) else { return }
                session.setDrumGroupSelectedPatternIndex(newValue, groupID: navigationState.groupID)
            }
        )
    }

    /// Matrix-wide layer selector: the same layer set the single-track step
    /// editor offers (steps, velocity, chance), applied to every part row.
    var layerSelector: some View {
        HStack(spacing: 4) {
            ForEach(DrumKitMatrixLayer.allCases) { layer in
                layerButton(layer)
            }
        }
        .padding(3)
        .background(
            Color.white.opacity(StudioOpacity.subtleFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(StudioTheme.border.opacity(0.9), lineWidth: StudioMetrics.borderWidth)
        )
    }

    func layerButton(_ layer: DrumKitMatrixLayer) -> some View {
        let isSelected = selectedLayer == layer

        return Button {
            selectedLayer = layer
        } label: {
            Text(layer.title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78))
                .lineLimit(1)
                .frame(minWidth: 64, minHeight: 28)
                .padding(.horizontal, 8)
                .background(
                    isSelected ? accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step layer \(layer.title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    var mismatchBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(StudioTheme.background)
            Text("PATTERN MISMATCH")
                .studioText(.microEmphasis)
                .tracking(0.6)
                .foregroundStyle(StudioTheme.background)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(StudioTheme.amber, in: Capsule())
        .help("Pattern mismatch: parts are showing different active pattern slots.")
        .accessibilityLabel("Pattern mismatch: parts are showing different active pattern slots.")
    }

    func staleMemberBanner(count: Int) -> some View {
        Text("\(count) stale member ID\(count == 1 ? "" : "s") skipped")
            .studioText(.label)
            .foregroundStyle(StudioTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
    }

    var emptyRowsState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No resolved parts")
                .studioText(.bodyEmphasis)
                .foregroundStyle(StudioTheme.text)
            Text("This kit has no current member tracks to display.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.loose)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    func matrixRows(_ model: DrumKitMatrixModel) -> some View {
        let pageOffset = clampedPage(model) * Self.stepsPerBar
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.rows) { row in
                    DrumKitMatrixRowView(
                        row: row,
                        layer: selectedLayer,
                        pageOffset: pageOffset,
                        stepsPerBar: Self.stepsPerBar,
                        accent: accent,
                        isExpanded: expandedPartID == row.memberID,
                        onTapStep: { stepIndex in
                            commitTap(row: row, stepIndex: stepIndex)
                        },
                        onDragStep: { stepIndex, fraction in
                            commitDrag(row: row, stepIndex: stepIndex, fraction: fraction)
                        },
                        onToggleExpand: {
                            toggleExpand(memberID: row.memberID)
                        },
                        detailPanel: {
                            expandedRowDetail(row)
                        }
                    )
                }
            }
        }
        .scrollIndicators(.never)
    }

    /// Toggle a row's inline accordion (AC21). Resets the mini-tab to Steps/Clip
    /// on a fresh expand so the row always opens on the same surface.
    func toggleExpand(memberID: UUID) {
        if expandedPartID == memberID {
            expandedPartID = nil
        } else {
            expandedPartID = memberID
            expandedRowTab = .stepsClip
        }
        postRenderedVisualState(isVisible: true)
    }
}
