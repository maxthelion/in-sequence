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

    /// Kit-level FILL / NORMAL control for the matrix top bar (applies to all
    /// rows). NORMAL hears phrase-resolved playback; FILL previews the fill lane.
    /// Fill preview is single-track in the engine, so this addresses the kit's
    /// representative member (the originating part, falling back to the first
    /// row). Disabled when that part's source has no fill lane to preview.
    func fillModeControl(_ model: DrumKitMatrixModel) -> some View {
        let memberID = fillPreviewMemberID(model)
        let isActive = memberID.map { session.isTrackFillPreviewActive(trackID: $0) } ?? false
        let isAvailable = memberID.map { session.isTrackFillPreviewAvailable(trackID: $0) } ?? false
        return HStack(spacing: 4) {
            fillModeButton(title: "Normal", isSelected: !isActive, isEnabled: true) {
                if let memberID { session.setTrackFillPreview(trackID: memberID, active: false) }
            }
            fillModeButton(title: "Fill", isSelected: isActive, isEnabled: isAvailable) {
                if let memberID { session.setTrackFillPreview(trackID: memberID, active: true) }
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
        .help(isAvailable
            ? "Switch all rows between NORMAL playback and the FILL lane preview"
            : "Fill preview is available for clip-backed kits only in v1")
        .accessibilityIdentifier("kit-fill-mode")
    }

    private func fillPreviewMemberID(_ model: DrumKitMatrixModel) -> UUID? {
        if model.rows.contains(where: { $0.memberID == navigationState.originatingPartID }) {
            return navigationState.originatingPartID
        }
        return model.rows.first?.memberID
    }

    func fillModeButton(
        title: String,
        isSelected: Bool,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78))
                .lineLimit(1)
                .frame(minWidth: 56, minHeight: 28)
                .padding(.horizontal, 8)
                .background(
                    isSelected ? accent : Color.clear,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel("\(title) playback")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Step layer \(layer.title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
