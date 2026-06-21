import SwiftUI

// Capture / History surface for the kit matrix (AC14/AC15/AC16): the header,
// scrubber, per-part windowed previews, save-slot picker, plus the shared
// window math, audition overrides, and coordinated save. Split out of
// DrumKitMatrixView.swift as an extension; zero behavior change.

extension DrumKitMatrixView {
    // MARK: - Capture / History body (AC14/AC15/AC16)

    /// One 16-step bar = the scrubber's quantum.
    static let historyStepsPerBar = 16
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
        return StudioPanel(title: "Capture · History", accent: accent) {
            VStack(alignment: .leading, spacing: 14) {
                captureHistoryHeader(model)
                captureHistoryScrubber(model, snapshots: snapshots)
                captureHistoryParts(model, snapshots: snapshots)
                captureHistoryFooter(model)
            }
        }
    }

    /// One snapshot per member, taken once per render and threaded down to the
    /// scrubber and the per-part preview helpers so each member's rolling buffer
    /// is locked + copied exactly once.
    func captureSnapshots(_ model: DrumKitMatrixModel) -> [UUID: CaptureSnapshot] {
        var snapshots: [UUID: CaptureSnapshot] = [:]
        snapshots.reserveCapacity(model.rows.count)
        for row in model.rows where snapshots[row.memberID] == nil {
            snapshots[row.memberID] = engineController.captureSnapshot(trackID: row.memberID)
        }
        return snapshots
    }

    func captureHistoryHeader(_ model: DrumKitMatrixModel) -> some View {
        HStack(spacing: 10) {
            Button {
                isCaptureOpen = false
            } label: {
                Label("Close capture", systemImage: "chevron.left")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("kit-capture-close")
            .accessibilityLabel("Close capture")

            Spacer(minLength: 0)

            captureAuditionButton(model)

            historyLengthControl
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
                    on ? StudioTheme.success : Color.white.opacity(StudioOpacity.subtleFill),
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
            Text("LENGTH")
                .studioText(.eyebrow)
                .tracking(0.8)
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
            Text("HISTORY")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

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
                        back == 0 ? accent : Color.white.opacity(StudioOpacity.subtleFill),
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
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
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
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("SELECTION → P\(targetSlot + 1)")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Text("\(lengthLabel) that saves into the pattern")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            }

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
            .frame(maxHeight: 260)
            .scrollIndicators(.never)
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
        let snapshot = snapshot ?? engineController.captureSnapshot(trackID: row.memberID)
        return HStack(spacing: 10) {
            Text(row.partName)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 120, alignment: .leading)

            ClipHistoryPianoRollPreview(
                content: historyFullBufferContent(snapshot: snapshot, memberID: row.memberID),
                gridSteps: historyDisplayedGridSteps(snapshot: snapshot),
                liveFillStepIndex: nil,
                accent: accent,
                isTransportRunning: engineController.isRunning,
                selectionRange: historySelectionRange(snapshot: snapshot)
            )
            .frame(height: 56)
            .frame(maxWidth: .infinity)
        }
    }

    func captureHistoryFooter(_ model: DrumKitMatrixModel) -> some View {
        HStack(spacing: 10) {
            if let message = historySaveMessage {
                Text(message)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.success)
            }

            Spacer(minLength: 0)

            Button {
                isPresentingSaveSlotPicker.toggle()
            } label: {
                Label("Save capture", systemImage: "tray.and.arrow.down")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.background)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Save each part's windowed selection into a chosen pattern slot as one coordinated clip set")
            .accessibilityIdentifier("kit-history-save")
            .accessibilityLabel("Save kit capture")
            .popover(isPresented: $isPresentingSaveSlotPicker, arrowEdge: .bottom) {
                captureSaveSlotPicker(model)
            }
        }
    }

    /// Save-slot picker (AC15): a 4×4 grid of P1–P16 slot buttons. Picking a
    /// slot saves each part's windowed selection into that slot as one
    /// coordinated clip set. Occupied slots read with the accent border so the
    /// user can see what is already assigned.
    func captureSaveSlotPicker(_ model: DrumKitMatrixModel) -> some View {
        let occupied = model.occupiedSlotIndexes
        return VStack(alignment: .leading, spacing: 10) {
            Text("Save capture to slot")
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
            Text("Each part's selection saves into the chosen slot as one clip set.")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)

            LazyVGrid(columns: captureSaveSlotColumns, spacing: 6) {
                ForEach(0..<TrackPatternBank.slotCount, id: \.self) { slotIndex in
                    captureSaveSlotButton(model, slotIndex: slotIndex, isOccupied: occupied.contains(slotIndex))
                }
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .frame(width: 280)
        .background(StudioTheme.stageFill)
    }

    var captureSaveSlotColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    }

    func captureSaveSlotButton(
        _ model: DrumKitMatrixModel,
        slotIndex: Int,
        isOccupied: Bool
    ) -> some View {
        let title = "P\(slotIndex + 1)"
        return Button {
            isPresentingSaveSlotPicker = false
            saveKitHistoryClipSet(model, slotIndex: slotIndex)
        } label: {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    Color.white.opacity(StudioOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(isOccupied ? accent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
        .help(isOccupied ? "\(title) (occupied) — save the capture here" : "Save the capture into \(title)")
        .accessibilityIdentifier("kit-history-save-slot-\(slotIndex + 1)")
        .accessibilityLabel("Save capture to \(title)")
        .accessibilityValue(isOccupied ? "Occupied" : "Empty")
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
                ?? engineController.captureSnapshot(trackID: row.memberID)
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
        let liveStart = max(0, maxSteps - historyLengthSteps)
        let back = min(historyBarsBack, historyMaxBarsBackForSteps(maxSteps))
        return max(0, liveStart - back * Self.historyStepsPerBar)
    }

    func historyMaxBarsBackForSteps(_ maxSteps: Int) -> Int {
        max(0, (maxSteps - historyLengthSteps)) / Self.historyStepsPerBar
    }

    /// The shared window's content materialized against one member's rolling
    /// buffer (AC15/AC16). Reuses `PseudoClipState`, the same materializer the
    /// single-track history uses.
    func historyWindowContent(memberID: UUID) -> ClipContent? {
        let snapshot = engineController.captureSnapshot(trackID: memberID)
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
    /// matched to what the single-track Recent Output covers (8 cells × the
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
        let snapshot = engineController.captureSnapshot(trackID: memberID)
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
            historySaveMessage = "Nothing to capture yet — play the kit first."
        }
        stopKitAudition()
        postRenderedVisualState(isVisible: true)
    }
}
