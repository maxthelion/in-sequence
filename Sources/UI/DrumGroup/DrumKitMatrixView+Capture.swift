import SwiftUI

// Capture / History surface for the kit matrix (AC14/AC15/AC16): the header,
// scrubber, per-part windowed previews, top-row save target mode, plus the shared
// window math, audition overrides, and coordinated save. Split out of
// DrumKitMatrixView.swift as an extension; zero behavior change.

extension DrumKitMatrixView {
    // MARK: - Capture / History body (AC14/AC15/AC16)

    /// One 16-step bar = the scrubber's quantum.
    static let historyStepsPerBar = 16
    /// The kit capture navigator mirrors the 16-slot pattern row: one compact
    /// bar cell for each whole bar of reachable history.
    static let historyNavigationCellCount = 16
    /// ½ / 1 / 2 / 4 bars, the shared selection-length options (AC16). Reuses
    /// the single-track clip-history length set so the windows match.
    static let historyLengthOptions = PseudoClipState.supportedLengthSteps

    /// Capture surface (AC14/AC15/AC16). Replaces the tab content while the
    /// Patterns row stays above (AC12). Shows EVERY member's live rolling
    /// buffer together, a shared scrubber that moves one selection window
    /// across all parts in lockstep, and a "Save as clip set → slot" action
    /// that writes each member's windowed selection into one coordinated set.
    @ViewBuilder
    func captureHistoryBody(_ model: DrumKitMatrixModel) -> some View {
        // Snapshot every member's rolling buffer ONCE per render. Each
        // `engineController.captureSnapshot(trackID:)` takes a lock and copies
        // the buffer; the scrubber + each part row's three preview helpers used
        // to call it 3–4× per part per render. Capturing here and threading the
        // map down collapses that to one snapshot per member per render.
        let snapshots = captureSnapshots(model)
        VStack(alignment: .leading, spacing: 14) {
            captureHistoryBar(model, snapshots: snapshots)
            VStack(alignment: .leading, spacing: 12) {
                captureHistoryParts(model, snapshots: snapshots)
            }
            .padding(StudioMetrics.Spacing.comfortable)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    /// One snapshot per member, taken once per render and threaded down to the
    /// scrubber and the per-part preview helpers so each member's rolling buffer
    /// is locked + copied exactly once.
    func captureSnapshots(_ model: DrumKitMatrixModel) -> [UUID: CaptureSnapshot] {
        var snapshots: [UUID: CaptureSnapshot] = [:]
        snapshots.reserveCapacity(model.rows.count)
        for row in model.rows where snapshots[row.memberID] == nil {
            snapshots[row.memberID] = captureSnapshot(memberID: row.memberID)
        }
        return snapshots
    }

    func captureSnapshot(memberID: UUID) -> CaptureSnapshot {
        visualCaptureSnapshots[memberID] ?? engineController.captureSnapshot(trackID: memberID)
    }

    func captureHistoryBar(
        _ model: DrumKitMatrixModel,
        snapshots: [UUID: CaptureSnapshot]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                historyLengthControl

                if let historySaveMessage {
                    Text(historySaveMessage)
                        .studioText(.label)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Button {
                    isSelectingCaptureSaveSlot = true
                    historySaveMessage = nil
                    postRenderedVisualState(isVisible: true)
                } label: {
                    Label(isSelectingCaptureSaveSlot ? "Choose slot" : "Save", systemImage: "tray.and.arrow.down")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.background)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Choose a pattern slot above to save each part's selected history window")
                .accessibilityIdentifier("kit-history-save")
                .accessibilityLabel("Save kit capture")

                StudioCircleIconButton(
                    systemName: "xmark",
                    size: StudioMetrics.ControlSize.medium,
                    help: "Close capture"
                ) {
                    isCaptureOpen = false
                    isSelectingCaptureSaveSlot = false
                    visualCaptureSnapshots = [:]
                    postRenderedVisualState(isVisible: true)
                }
                .accessibilityIdentifier("kit-capture-close")
                .accessibilityLabel("Close capture")
            }

            captureHistoryCellStrip(model, snapshots: snapshots)
                .frame(maxWidth: .infinity)
        }
        .padding(StudioMetrics.Spacing.compact)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    func captureHistoryMiniBar(
        _ model: DrumKitMatrixModel,
        snapshots: [UUID: CaptureSnapshot]
    ) -> some View {
        captureHistoryCellStrip(model, snapshots: snapshots)
    }

    func captureHistoryCellStrip(
        _ model: DrumKitMatrixModel,
        snapshots: [UUID: CaptureSnapshot]
    ) -> some View {
        let availableMaxBack = historyMaxBarsBack(model, snapshots: snapshots)
        let maxBack = Self.historyNavigationCellCount - 1
        let selectedBack = min(historyBarsBack, maxBack)
        let cellCount = Self.historyNavigationCellCount
        let selectedIndex = maxBack - selectedBack
        let coveredCells = max(1, Int(ceil(Double(historyLengthSteps) / Double(Self.historyStepsPerBar))))
        let columns = Array(repeating: GridItem(.flexible(minimum: 48), spacing: 4), count: cellCount)

        return LazyVGrid(columns: columns, spacing: 0) {
            ForEach(0..<cellCount, id: \.self) { index in
                let back = maxBack - index
                let partStates = kitHistoryCellPartStepStates(model, snapshots: snapshots, barsBack: back)
                let isAvailable = back <= availableMaxBack
                let isSelectable = isAvailable && partStates.contains { $0.contains(true) }
                KitHistoryMinibarCell(
                    index: index,
                    partStepStates: partStates,
                    isSelected: index == selectedIndex,
                    isInRange: index >= selectedIndex && index < selectedIndex + coveredCells,
                    isAvailable: isAvailable,
                    accent: accent
                ) {
                    historyBarsBack = back
                    historySaveMessage = nil
                    refreshKitAuditionIfActive()
                    postRenderedVisualState(isVisible: true)
                }
                .disabled(!isSelectable)
                .help(back == 0 ? "Most recent capture window" : "\(back) bar\(back == 1 ? "" : "s") back")
                .accessibilityIdentifier("kit-history-cell-\(index)")
            }
        }
    }

    /// Shared Preview/Audition toggle (AC15). When ON, sets every member's
    /// audition override to its windowed pseudo-clip so the whole kit plays the
    /// selected window as its clips; when OFF, clears every override. Reuses
    /// `engineController.setAuditionOverride(_:for:)` per member.
    func captureAuditionButton(_ model: DrumKitMatrixModel) -> some View {
        let on = isAuditioningCapture
        return Button {
            toggleKitAudition(model)
        } label: {
            Label(on ? "Auditioning" : "Audition", systemImage: on ? "stop.fill" : "play.fill")
                .studioText(.labelBold)
                .foregroundStyle(on ? StudioTheme.background : StudioTheme.text)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    on ? accent : StudioTheme.subtleFill,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(on ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
        .help("Audition: play the selected window as the clips for every part")
        .accessibilityIdentifier("kit-history-audition")
        .accessibilityLabel("Audition kit history")
        .accessibilityValue(on ? "On" : "Off")
    }

    /// Shared ½/1/2/4-bar selection-length control (AC16). Applies to every
    /// member's window at once.
    var historyLengthControl: some View {
        HStack(spacing: 8) {
            Text("Length")
                .studioText(.microEmphasis)
                .foregroundStyle(StudioTheme.mutedText)

            StudioSegmentedControl(
                title: nil,
                selection: Binding(
                    get: { historyLengthSteps },
                    set: { option in
                        historyLengthSteps = option
                        historySaveMessage = nil
                        refreshKitAuditionIfActive()
                        postRenderedVisualState(isVisible: true)
                    }
                ),
                segments: Self.historyLengthOptions.map { option in
                    let title = ClipHistoryTransferViewModel.lengthLabel(for: option)
                    return StudioSegment(
                        title: title,
                        value: option,
                        accessibilityIdentifier: "kit-history-length-\(option)",
                        accessibilityLabel: "Selection length \(title)"
                    )
                },
                accent: accent,
                layout: StudioSegmentedControl.Layout(
                    fillsWidth: false,
                    minWidth: 52,
                    minHeight: 26,
                    horizontalPadding: 6,
                    minimumScaleFactor: nil
                )
            )
        }
    }

    /// Shared scrubber/timeline (AC16). « steps the window back through the
    /// rolling buffer, » steps it toward now, and Live jumps to the newest
    /// window. The window position is shown ("live" vs "N back"). The same
    /// window applies to every member row in lockstep.
    func captureHistoryScrubber(
        _ model: DrumKitMatrixModel,
        snapshots: [UUID: CaptureSnapshot]
    ) -> some View {
        let maxBack = historyMaxBarsBack(model, snapshots: snapshots)
        let back = min(historyBarsBack, maxBack)
        return HStack(spacing: 10) {
            historyScrubButton(
                systemImage: "chevron.left.2",
                id: "kit-history-scrub-back",
                label: "Scrub back in time",
                enabled: back < maxBack
            ) {
                historyScrubBack(model)
            }

            historyScrubButton(
                systemImage: "chevron.right.2",
                id: "kit-history-scrub-forward",
                label: "Scrub toward now",
                enabled: back > 0
            ) {
                historyScrubForward()
            }

            Button {
                historyJumpToLive()
            } label: {
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
                    .studioText(.labelBold)
                    .foregroundStyle(back == 0 ? StudioTheme.background : StudioTheme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        back == 0 ? accent : StudioTheme.subtleFill,
                        in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(back == 0 ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
            }
            .buttonStyle(.plain)
            .help("Jump the selection window to the live edge (now)")
            .accessibilityIdentifier("kit-history-live")
            .accessibilityLabel("Jump to live")

            if back > 0 {
                Text("◂ \(back) bar\(back == 1 ? "" : "s") back")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .accessibilityIdentifier("kit-history-window")
                    .accessibilityLabel("History window position")
            }

            if let historySaveMessage {
                Text(historySaveMessage)
                    .studioText(.label)
                    .foregroundStyle(accent)
            }

            Spacer(minLength: 0)
        }
    }

    func historyScrubButton(
        systemImage: String,
        id: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? StudioTheme.text : StudioTheme.mutedText)
                .frame(width: 32, height: 30)
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(label)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }

    /// All members' windowed buffers, one compact strip each (AC15). Every
    /// strip previews the SAME shared window resolved against that member's
    /// own rolling snapshot, so the parts read together.
    /// The length-defined window that will be written into the pattern — the
    /// preview of what Save captures, distinct from the History scrubber above
    /// (which navigates the rolling buffer). Reuses the single-track
    /// `ClipHistoryPianoRollPreview` per part rather than a bespoke strip.
    func captureHistoryParts(
        _ model: DrumKitMatrixModel,
        snapshots: [UUID: CaptureSnapshot]
    ) -> some View {
        let targetSlot = historyTargetSlotIndex(model)
        let lengthLabel = ClipHistoryTransferViewModel.lengthLabel(for: historyLengthSteps)
        let previewHeight = min(max(CGFloat(model.rows.count) * 40, 160), 260)
        return VStack(alignment: .leading, spacing: 8) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.rows) { row in
                        captureHistoryPartRow(
                            row,
                            snapshot: snapshots[row.memberID]
                        )
                    }
                }
            }
            .frame(minHeight: previewHeight, maxHeight: previewHeight)
            .scrollIndicators(.never)
            .help("The \(lengthLabel) window Save writes into pattern slot P\(targetSlot + 1)")
        }
    }

    /// One part's longer-history row: the full rolling buffer drawn as a piano
    /// roll, with the length-defined save-window highlighted via the reused
    /// `ClipHistoryPianoRollPreview.selectionRange`.
    func captureHistoryPartRow(
        _ row: DrumKitMatrixModel.Row,
        snapshot: CaptureSnapshot?
    ) -> some View {
        // One snapshot drives all three previews for this row (full buffer,
        // grid step count, selection highlight) instead of three separate locks.
        let snapshot = snapshot ?? captureSnapshot(memberID: row.memberID)
        return HStack(spacing: 10) {
            Text(row.partName)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 120, alignment: .leading)

            captureTriggeredStepStrip(snapshot: snapshot, memberID: row.memberID)
                .frame(height: 28)
            .frame(maxWidth: .infinity)
        }
    }

    func captureTriggeredStepStrip(snapshot: CaptureSnapshot, memberID: UUID) -> some View {
        let states: [Bool] = {
            guard let content = historyWindowContent(memberID: memberID, snapshot: snapshot),
                  case let .noteGrid(_, steps) = content
            else {
                return Array(repeating: false, count: historyLengthSteps)
            }
            return steps.map { !$0.isEmpty }
        }()
        return HStack(spacing: 3) {
            ForEach(Array(states.enumerated()), id: \.offset) { index, isTriggered in
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                    .fill(isTriggered ? accent : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.mini, style: .continuous)
                            .stroke(isTriggered ? accent : StudioTheme.border.opacity(StudioOpacity.softStroke), lineWidth: StudioMetrics.borderWidth)
                    )
                    .help("Step \(index + 1)")
            }
        }
    }

    func kitHistoryCellStepStates(
        _ model: DrumKitMatrixModel,
        snapshots: [UUID: CaptureSnapshot],
        barsBack: Int
    ) -> [Bool] {
        let rowStates = kitHistoryCellPartStepStates(model, snapshots: snapshots, barsBack: barsBack)
        return rowStates.reduce(Array(repeating: false, count: Self.historyStepsPerBar)) { combined, row in
            var next = combined
            for (index, value) in row.enumerated() where index < next.count && value {
                next[index] = true
            }
            return next
        }
    }

    func kitHistoryCellPartStepStates(
        _ model: DrumKitMatrixModel,
        snapshots: [UUID: CaptureSnapshot],
        barsBack: Int
    ) -> [[Bool]] {
        model.rows.map { row in
            let snapshot = snapshots[row.memberID] ?? captureSnapshot(memberID: row.memberID)
            return kitHistoryCellStepStates(row: row, snapshot: snapshot, barsBack: barsBack)
        }
    }

    private func kitHistoryCellStepStates(
        row: DrumKitMatrixModel.Row,
        snapshot: CaptureSnapshot,
        barsBack: Int
    ) -> [Bool] {
        var states = Array(repeating: false, count: Self.historyStepsPerBar)
        guard !snapshot.isEmpty else { return Array(repeating: false, count: Self.historyStepsPerBar) }
        let content = PseudoClipState.materialize(
            sourceTrackID: row.memberID,
            from: snapshot,
            startStep: historyWindowStartOffset(maxSteps: snapshot.maxSteps, barsBack: barsBack),
            lengthSteps: Self.historyStepsPerBar
        ).noteGrid
        guard case let .noteGrid(_, steps) = content else {
            return Array(repeating: false, count: Self.historyStepsPerBar)
        }
        for (index, step) in steps.enumerated() where index < states.count {
            if !step.isEmpty {
                states[index] = true
            }
        }
        return states
    }

    // MARK: - Kit history window math + save (AC15/AC16)

    /// The slot a coordinated save targets: the shared group slot when members
    /// agree, otherwise the first member's slot.
    func historyTargetSlotIndex(_ model: DrumKitMatrixModel) -> Int {
        model.groupSelectedSlotIndex ?? model.rows.first?.patternSlotIndex ?? 0
    }

    /// How many whole bars back the scrubber can travel before running out of
    /// buffer — bounded by the shortest member snapshot so the window stays
    /// valid for EVERY part in lockstep.
    func historyMaxBarsBack(_ model: DrumKitMatrixModel) -> Int {
        historyMaxBarsBack(model, snapshots: captureSnapshots(model))
    }

    /// Same as `historyMaxBarsBack(_:)` but reuses pre-taken snapshots so the
    /// render path doesn't re-lock every member's buffer.
    func historyMaxBarsBack(
        _ model: DrumKitMatrixModel,
        snapshots: [UUID: CaptureSnapshot]
    ) -> Int {
        var minMaxSteps = Int.max
        for row in model.rows {
            let snapshot = snapshots[row.memberID]
                ?? captureSnapshot(memberID: row.memberID)
            minMaxSteps = min(minMaxSteps, snapshot.maxSteps)
        }
        guard minMaxSteps != Int.max else { return 0 }
        let usableSteps = max(0, minMaxSteps - historyLengthSteps)
        return usableSteps / Self.historyStepsPerBar
    }

    /// Resolve the shared window's start offset into a member snapshot. Offset 0
    /// is the buffer's oldest step; the live edge is `maxSteps - length`, and
    /// each bar back subtracts one bar. Clamped so it never underflows.
    func historyWindowStartOffset(maxSteps: Int) -> Int {
        historyWindowStartOffset(maxSteps: maxSteps, barsBack: historyBarsBack)
    }

    func historyWindowStartOffset(maxSteps: Int, barsBack: Int) -> Int {
        let liveStart = max(0, maxSteps - historyLengthSteps)
        let back = min(barsBack, historyMaxBarsBackForSteps(maxSteps))
        return max(0, liveStart - back * Self.historyStepsPerBar)
    }

    func historyMaxBarsBackForSteps(_ maxSteps: Int) -> Int {
        max(0, (maxSteps - historyLengthSteps)) / Self.historyStepsPerBar
    }

    /// The shared window's content materialized against one member's rolling
    /// buffer (AC15/AC16). Reuses `PseudoClipState`, the same materializer the
    /// single-track history uses.
    func historyWindowContent(memberID: UUID) -> ClipContent? {
        let snapshot = captureSnapshot(memberID: memberID)
        return historyWindowContent(memberID: memberID, snapshot: snapshot)
    }

    func historyWindowContent(memberID: UUID, snapshot: CaptureSnapshot) -> ClipContent? {
        guard !snapshot.isEmpty else { return nil }
        return PseudoClipState.materialize(
            sourceTrackID: memberID,
            from: snapshot,
            startStep: historyWindowStartOffset(maxSteps: snapshot.maxSteps),
            lengthSteps: historyLengthSteps
        ).noteGrid
    }

    /// How many steps of a member's rolling buffer to display behind the
    /// selection window — the longer history. Capped so the row stays readable;
    /// matched to what the single-track history strip covers (8 cells × the
    /// per-cell step count).
    static let historyDisplayedBufferCap =
        ClipHistoryTransferViewModel.sourceCellCount * ClipHistoryTransferViewModel.stepsPerCell

    /// Number of buffer steps shown for a member: the snapshot's available
    /// steps, capped to keep the row readable.
    func historyDisplayedBufferSteps(maxSteps: Int) -> Int {
        max(historyLengthSteps, min(maxSteps, Self.historyDisplayedBufferCap))
    }

    /// The FULL displayed buffer for a member (the longer history), materialized
    /// against the tail of its rolling snapshot. Reuses `PseudoClipState`, the
    /// same materializer the windowed selection uses.
    func historyFullBufferContent(snapshot: CaptureSnapshot, memberID: UUID) -> ClipContent? {
        guard !snapshot.isEmpty else { return nil }
        let displayed = historyDisplayedBufferSteps(maxSteps: snapshot.maxSteps)
        let bufferStart = max(0, snapshot.maxSteps - displayed)
        return PseudoClipState.materialize(
            sourceTrackID: memberID,
            from: snapshot,
            startStep: bufferStart,
            lengthSteps: displayed
        ).noteGrid
    }

    /// The save-window's step columns within the DISPLAYED buffer for a member:
    /// `[windowStart, windowStart + length)` re-based onto the shown buffer so
    /// the highlight lines up with `historyFullBufferContent`.
    func historySelectionRange(snapshot: CaptureSnapshot) -> Range<Int> {
        guard !snapshot.isEmpty else { return 0..<historyLengthSteps }
        let displayed = historyDisplayedBufferSteps(maxSteps: snapshot.maxSteps)
        let bufferStart = max(0, snapshot.maxSteps - displayed)
        let windowStart = historyWindowStartOffset(maxSteps: snapshot.maxSteps)
        let relativeStart = max(0, windowStart - bufferStart)
        let relativeEnd = min(displayed, relativeStart + historyLengthSteps)
        return relativeStart..<max(relativeStart, relativeEnd)
    }

    /// Number of grid columns the full-buffer preview should draw for a member.
    func historyDisplayedGridSteps(snapshot: CaptureSnapshot) -> Int {
        guard !snapshot.isEmpty else { return historyLengthSteps }
        return historyDisplayedBufferSteps(maxSteps: snapshot.maxSteps)
    }

    func historyScrubBack(_ model: DrumKitMatrixModel) {
        let maxBack = historyMaxBarsBack(model)
        guard historyBarsBack < maxBack else { return }
        historyBarsBack += 1
        historySaveMessage = nil
        refreshKitAuditionIfActive()
        postRenderedVisualState(isVisible: true)
    }

    func historyScrubForward() {
        guard historyBarsBack > 0 else { return }
        historyBarsBack -= 1
        historySaveMessage = nil
        refreshKitAuditionIfActive()
        postRenderedVisualState(isVisible: true)
    }

    func historyJumpToLive() {
        historyBarsBack = 0
        historySaveMessage = nil
        refreshKitAuditionIfActive()
        postRenderedVisualState(isVisible: true)
    }

    // MARK: - Kit capture audition (AC15)

    func toggleKitAudition(_ model: DrumKitMatrixModel) {
        if isAuditioningCapture {
            stopKitAudition(model)
        } else {
            startKitAudition(model)
        }
    }

    /// Set every member's audition override to its windowed pseudo-clip so the
    /// whole kit plays the selected window as its clips.
    func startKitAudition(_ model: DrumKitMatrixModel) {
        for row in model.rows {
            applyMemberAuditionOverride(memberID: row.memberID)
        }
        isAuditioningCapture = true
        postRenderedVisualState(isVisible: true)
    }

    /// Clear every member's audition override.
    func stopKitAudition(_ model: DrumKitMatrixModel) {
        for row in model.rows {
            engineController.setAuditionOverride(nil, for: row.memberID)
        }
        isAuditioningCapture = false
        postRenderedVisualState(isVisible: true)
    }

    /// Clear all overrides without needing the model (capture close / disappear).
    func stopKitAudition() {
        guard isAuditioningCapture else { return }
        if let model {
            for row in model.rows {
                engineController.setAuditionOverride(nil, for: row.memberID)
            }
        }
        isAuditioningCapture = false
    }

    /// Re-apply overrides for the current window when the selection moves while
    /// auditioning, so the playing clips track the scrubber/length.
    func refreshKitAuditionIfActive() {
        guard isAuditioningCapture, let model else { return }
        for row in model.rows {
            applyMemberAuditionOverride(memberID: row.memberID)
        }
    }

    func applyMemberAuditionOverride(memberID: UUID) {
        let snapshot = captureSnapshot(memberID: memberID)
        guard !snapshot.isEmpty else {
            engineController.setAuditionOverride(nil, for: memberID)
            return
        }
        let state = PseudoClipState.materialize(
            sourceTrackID: memberID,
            from: snapshot,
            startStep: historyWindowStartOffset(maxSteps: snapshot.maxSteps),
            lengthSteps: historyLengthSteps
        )
        engineController.setAuditionOverride(state, for: memberID)
    }

    /// Save the shared window for EVERY member into one coordinated clip set at
    /// the same pattern slot (AC15). Reuses the single-track save-to-slot path
    /// (`saveMaterializedClipToPatternSlot`) once per member, targeting the
    /// identical slot index so the result is one assignable set.
    func saveKitHistoryClipSet(_ model: DrumKitMatrixModel, slotIndex: Int) {
        var savedCount = 0
        for row in model.rows {
            guard let content = historyWindowContent(memberID: row.memberID) else { continue }
            let clipID = session.saveMaterializedClipToPatternSlot(
                trackID: row.memberID,
                slotIndex: slotIndex,
                content: content,
                name: "Kit Capture P\(slotIndex + 1)"
            )
            if clipID != nil { savedCount += 1 }
        }
        if savedCount > 0 {
            historySaveMessage = "Saved \(savedCount) part\(savedCount == 1 ? "" : "s") to P\(slotIndex + 1)"
        } else {
            historySaveMessage = "No captured history"
        }
        isSelectingCaptureSaveSlot = false
        isCaptureOpen = false
        patternTemplateTargets.clear()
        stopKitAudition()
        postRenderedVisualState(isVisible: true)
    }

    func seedVisualCaptureHistory(_ model: DrumKitMatrixModel) {
        let patterns: [[Int]] = [
            [0, 4, 8, 12],
            [4, 12],
            [2, 6, 10, 14],
            [6, 14],
            [3, 11],
            [2, 10],
            [0, 7, 12],
            [5, 13],
        ]
        var snapshots: [UUID: CaptureSnapshot] = [:]
        snapshots.reserveCapacity(model.rows.count)
        for (rowIndex, row) in model.rows.enumerated() {
            let activeOffsets = patterns[rowIndex % patterns.count]
            var steps = (0..<Self.historyNavigationCellCount).flatMap { barIndex in
                activeOffsets.map { offset in
                    barIndex * Self.historyStepsPerBar + offset
                }
            }.map { step in
                CaptureSnapshot.Step(
                    absoluteStep: step,
                    notes: [
                        CaptureSnapshot.Note(
                            pitch: 36 + rowIndex,
                            velocity: 100,
                            lengthSteps: 1,
                            voiceTag: nil
                        ),
                    ]
                )
            }
            steps.append(CaptureSnapshot.Step(absoluteStep: Self.historyNavigationCellCount * Self.historyStepsPerBar - 1, notes: []))
            snapshots[row.memberID] = CaptureSnapshot(maxSteps: Self.historyNavigationCellCount * Self.historyStepsPerBar, steps: steps)
        }
        visualCaptureSnapshots = snapshots
        historyBarsBack = 0
        historySaveMessage = nil
        refreshKitAuditionIfActive()
        postRenderedVisualState(isVisible: true)
    }

    func clearVisualCaptureHistory() {
        visualCaptureSnapshots = [:]
        refreshKitAuditionIfActive()
        postRenderedVisualState(isVisible: true)
    }
}

private struct KitHistoryMinibarCell: View {
    let index: Int
    let partStepStates: [[Bool]]
    let isSelected: Bool
    let isInRange: Bool
    let isAvailable: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KitHistoryMiniStepThumbnail(partStepStates: partStepStates, accent: accent, isAvailable: isAvailable)
                .frame(maxWidth: .infinity, minHeight: 48, maxHeight: 48)
            .padding(5)
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(borderFill, style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: isEmpty ? [4, 4] : []))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var isEmpty: Bool {
        !partStepStates.contains { $0.contains(true) }
    }

    private var borderFill: Color {
        if isSelected || isInRange {
            return accent
        }
        return StudioTheme.border
    }

    private var accessibilityLabel: String {
        if !isAvailable || isEmpty {
            return "Kit history region \(index + 1), empty"
        }
        return "Kit history region \(index + 1)"
    }
}

private struct KitHistoryMiniStepThumbnail: View {
    let partStepStates: [[Bool]]
    let accent: Color
    let isAvailable: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let height = max(geometry.size.height, 1)
            let stepCount = max(partStepStates.map(\.count).max() ?? 1, 1)
            let rowCount = max(partStepStates.count, 1)
            let stepWidth = width / CGFloat(stepCount)
            let rowGap: CGFloat = 2
            let rowHeight = max(2, (height - rowGap * CGFloat(max(0, rowCount - 1))) / CGFloat(rowCount))

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .fill(isAvailable ? StudioTheme.subtleFill : StudioTheme.panelFill)

                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { index in
                        Rectangle()
                            .fill(index.isMultiple(of: 2) ? StudioTheme.borderLowFill : Color.clear)
                            .frame(width: width / 4)
                    }
                }

                VStack(spacing: rowGap) {
                    ForEach(Array(partStepStates.enumerated()), id: \.offset) { _, rowStates in
                        HStack(spacing: 0) {
                            ForEach(Array(rowStates.enumerated()), id: \.offset) { _, isTriggered in
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(isTriggered && isAvailable ? accent : Color.clear)
                                    .frame(width: max(stepWidth, 2), height: rowHeight)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
    }
}
