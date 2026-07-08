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
    /// Locked grammar: a VALUE selector — the shared inset-track solid-thumb
    /// control INSIDE the well, never the pill-row grammar.
    var layerSelector: some View {
        StudioSegmentedControl(
            title: nil,
            selection: $selectedLayer,
            segments: DrumKitMatrixLayer.allCases.map { layer in
                StudioSegment(
                    title: layer.title,
                    value: layer,
                    accessibilityLabel: "Step layer \(layer.title)"
                )
            },
            accent: accent,
            layout: Self.matrixSelectorLayout(minWidth: 64)
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
        return StudioSegmentedControl(
            title: nil,
            selection: Binding(
                get: { isActive },
                set: { newValue in
                    if let memberID { session.setTrackFillPreview(trackID: memberID, active: newValue) }
                }
            ),
            segments: [
                StudioSegment(title: "Normal", value: false, accessibilityLabel: "Normal playback"),
                StudioSegment(title: "Fill", value: true, isEnabled: isAvailable, accessibilityLabel: "Fill playback"),
            ],
            accent: accent,
            layout: Self.matrixSelectorLayout(minWidth: 56)
        )
        .help(isAvailable
            ? "Switch all rows between NORMAL playback and the FILL lane preview"
            : "Fill preview is available for clip-backed kits only in v1")
        .accessibilityIdentifier("kit-fill-mode")
    }

    /// Shared chip geometry for the matrix top-bar value selectors (layer,
    /// fill, bar pager): hug-width chips matching the pre-migration bespoke
    /// buttons pixel-for-pixel.
    static func matrixSelectorLayout<Value: Equatable>(
        minWidth: CGFloat
    ) -> StudioSegmentedControl<Value>.Layout {
        StudioSegmentedControl<Value>.Layout(
            fillsWidth: false,
            minWidth: minWidth,
            minHeight: 28,
            horizontalPadding: 8,
            minimumScaleFactor: nil
        )
    }

    func fillPreviewMemberID(_ model: DrumKitMatrixModel) -> UUID? {
        if model.rows.contains(where: { $0.memberID == navigationState.originatingPartID }) {
            return navigationState.originatingPartID
        }
        return model.rows.first?.memberID
    }

    func matrixNoteLane(_ model: DrumKitMatrixModel?) -> StepGridNoteLane {
        guard let model,
              let memberID = fillPreviewMemberID(model),
              session.isTrackFillPreviewActive(trackID: memberID)
        else {
            return .main
        }
        return .fill
    }

    func matrixNoteLaneLabel(_ model: DrumKitMatrixModel?) -> String {
        switch matrixNoteLane(model) {
        case .main:
            return "main"
        case .fill:
            return "fill"
        }
    }

    func staleMemberBanner(count: Int) -> some View {
        Text("\(count) stale member ID\(count == 1 ? "" : "s") skipped")
            .studioText(.label)
            .foregroundStyle(StudioTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
    }

    var emptyRowsState: some View {
        // Canon Rule 3: state title only — the explanation lives in the tooltip.
        Text("No resolved parts")
            .studioText(.bodyEmphasis)
            .foregroundStyle(StudioTheme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(StudioMetrics.Spacing.loose)
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .help("This kit has no current member tracks to display")
    }

    func matrixRows(_ model: DrumKitMatrixModel) -> some View {
        let pageOffset = clampedPage(model) * Self.stepsPerBar
        let noteLane = matrixNoteLane(model)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(model.rows) { row in
                    DrumKitMatrixRowView(
                        row: row,
                        layer: selectedLayer,
                        noteLane: noteLane,
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
