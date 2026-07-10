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

    /// Matrix-wide layer selector using the same compact disclosure grammar as
    /// the single-track step editor. The disclosed row keeps every available
    /// layer visible without making four controls compete with matrix actions.
    var layerSelector: some View {
        StepLayerQuickSwitchChip(
            title: "",
            selection: $selectedLayer,
            isOpen: $isLayerSwitcherOpen,
            options: matrixLayerOptions,
            accent: accent
        )
        .accessibilityIdentifier("kit-matrix-layer-selector")
    }

    var matrixLayerOptions: [StepLayerQuickSwitchOption<DrumKitMatrixLayer>] {
        DrumKitMatrixLayer.allCases.map { layer in
            StepLayerQuickSwitchOption(id: layer.rawValue, title: layer.title, value: layer)
        }
    }

    var layerOptions: some View {
        StepLayerQuickSwitchOptions(
            selection: $selectedLayer,
            isOpen: $isLayerSwitcherOpen,
            options: matrixLayerOptions,
            accent: accent
        )
        .accessibilityIdentifier("kit-matrix-layer-options")
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

    func emptyRowsState(_ model: DrumKitMatrixModel) -> some View {
        // Canon Rule 3: state title only — the explanation lives in the tooltip.
        HStack(spacing: 12) {
            Text("No resolved parts")
                .studioText(.bodyEmphasis)
                .foregroundStyle(StudioTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            addPartButton(model)
        }
        .padding(StudioMetrics.Spacing.loose)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .help("This kit has no current member tracks to display")
    }

    func addPartButton(_ model: DrumKitMatrixModel) -> some View {
        Button {
            _ = session.addDefaultDrumPart(groupID: model.groupID)
        } label: {
            Label("Add Part", systemImage: "plus")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.background)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("Add a drum part to \(model.groupName)")
        .accessibilityIdentifier("kit-page-add-part")
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
                        selectedStepIndexes: selectedStepIndexes(for: row),
                        isExpanded: expandedPartID == row.memberID,
                        onTapStep: { stepIndex in
                            commitTap(row: row, stepIndex: stepIndex)
                        },
                        onDragStep: { stepIndex, fraction in
                            commitDrag(row: row, stepIndex: stepIndex, fraction: fraction)
                        },
                        onSelectStep: { stepIndex in
                            toggleStepSelection(row: row, stepIndex: stepIndex)
                        },
                        onClearSelection: clearDrumStepSelection,
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

    func selectedStepIndexes(for row: DrumKitMatrixModel.Row) -> Set<Int> {
        selectedStepMemberID == row.memberID ? selectedDrumStepIndexes : []
    }

    func toggleStepSelection(row: DrumKitMatrixModel.Row, stepIndex: Int) {
        if selectedStepMemberID != row.memberID {
            selectedStepMemberID = row.memberID
            selectedDrumStepIndexes.removeAll()
        }
        if selectedDrumStepIndexes.contains(stepIndex) {
            selectedDrumStepIndexes.remove(stepIndex)
        } else {
            selectedDrumStepIndexes.insert(stepIndex)
        }
        if selectedDrumStepIndexes.isEmpty {
            selectedStepMemberID = nil
        }
    }

    func clearDrumStepSelection() {
        selectedStepMemberID = nil
        selectedDrumStepIndexes.removeAll()
    }

    func selectedDrumRow(in model: DrumKitMatrixModel) -> DrumKitMatrixModel.Row? {
        guard let selectedStepMemberID else { return nil }
        return model.rows.first { $0.memberID == selectedStepMemberID }
    }

    func copySelectedDrumSteps(in model: DrumKitMatrixModel) {
        guard let row = selectedDrumRow(in: model),
              case let .editable(clipID?, _, _) = row.content,
              let clip = session.store.clipEntry(id: clipID),
              let track = memberTrack(row.memberID)
        else { return }

        let entries = Dictionary(uniqueKeysWithValues: selectedDrumStepIndexes.sorted().map { index in
            (index, ClipNoteGridStepEditing.clipboardEntry(at: index, in: clip, macroBindings: track.macros))
        })
        drumStepClipboard = StepClipboard(sourceClipID: clipID, steps: entries)
    }

    func clearSelectedDrumSteps(in model: DrumKitMatrixModel) {
        guard let row = selectedDrumRow(in: model),
              let track = memberTrack(row.memberID)
        else { return }
        let indexes = selectedDrumStepIndexes.sorted()
        session.ensureClipAndMutate(
            at: PatternSlotAddress(trackID: row.memberID, slotIndex: row.patternSlotIndex)
        ) { _, entry in
            for index in indexes {
                ClipNoteGridStepEditing.clearStep(at: index, entry: &entry, macroBindings: track.macros)
            }
        }
        clearDrumStepSelection()
    }

    func pasteDrumStepClipboard(in model: DrumKitMatrixModel) {
        guard let row = selectedDrumRow(in: model),
              let track = memberTrack(row.memberID),
              let drumStepClipboard
        else { return }
        session.ensureClipAndMutate(
            at: PatternSlotAddress(trackID: row.memberID, slotIndex: row.patternSlotIndex)
        ) { _, entry in
            for (index, clipboardEntry) in drumStepClipboard.steps {
                ClipNoteGridStepEditing.paste(
                    clipboardEntry,
                    at: index,
                    entry: &entry,
                    macroBindings: track.macros,
                    defaultNote: row.defaultNote
                )
            }
        }
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
