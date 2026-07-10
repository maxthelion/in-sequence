import SwiftUI

// Header chrome and bar pager for the kit matrix: the title/back/routing/
// capture/perform header, its button styles, and the 16-step bar pager. Split
// out of DrumKitMatrixView.swift as an extension; zero behavior change.

extension DrumKitMatrixView {
    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                if showsBackButton {
                    Button {
                        onBack()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .studioText(.labelBold)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(StudioTheme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                    Text(model?.groupName ?? "Kit")
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

                headerSecondaryButton(title: "Routing", systemImage: "slider.horizontal.3") {
                    isPresentingRoutingEditor = true
                }
                .help("Edit the kit's trigger routing and destinations")

                if let model, !model.rows.isEmpty {
                    headerActionButton(title: "Apply Template", systemImage: "square.grid.2x2") {
                        if patternTemplateTargets.requestTemplateChooser() {
                            isPresentingTemplateChooser = true
                        }
                    }
                    .help(templateApplyHelp)
                }

                captureButton

                performButton
            }

            if let model, !model.rows.isEmpty {
                headerPatternPalette(model)
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.hoverFill), lineWidth: StudioMetrics.borderWidth)
        )
    }

    /// The 1–16 kit-level pattern pills, now living inside the header box. The
    /// kit supports only KIT-level patterns, so the former Linked / MIXED /
    /// Re-link controls are gone — selecting a slot applies it across the kit.
    func headerPatternPalette(_ model: DrumKitMatrixModel) -> some View {
        let isCaptureDestination = isCaptureOpen && isSelectingCaptureSaveSlot
        return TrackPatternSlotPalette(
            selectedSlot: groupPatternSlotBinding(model),
            occupiedSlots: model.occupiedSlotIndexes,
            bypassState: .notApplicable,
            onBypassToggle: { _ in },
            playingSlot: playingPatternSlot(model),
            accent: accent,
            destinationMode: isCaptureDestination
                ? TrackPatternSlotPalette.DestinationMode(
                    pendingReplaceSlot: nil,
                    accent: accent
                )
                : nil,
            onDestinationSelect: { slotIndex in
                saveKitHistoryClipSet(model, slotIndex: slotIndex)
            },
            targetMode: isCaptureDestination
                ? nil
                : TrackPatternSlotPalette.TargetMode(
                    selectedSlots: patternTemplateTargets.slotIndexes,
                    isPrompting: patternTemplateTargets.isPrompting,
                    accent: accent
                ),
            onTargetSelect: { slotIndex, additive in
                clearDrumStepSelection()
                patternTemplateTargets.select(slotIndex: slotIndex, additive: additive)
            }
        )
    }

    private func playingPatternSlot(_ model: DrumKitMatrixModel) -> Int? {
        guard engineController.isRunning else { return nil }
        let playhead = PhrasePlayhead(
            phrase: session.store.selectedPhrase,
            transportTickIndex: engineController.transportTickIndex
        )
        let slots = Set(model.rows.map { row in
            engineController.activePatternSlotOverride(for: row.memberID)
                ?? playhead.patternIndex(
                    for: row.memberID,
                    patternLayer: session.store.patternLayer
                )
        })
        return slots.count == 1 ? slots.first : nil
    }

    private var templateApplyHelp: String {
        let slots = patternTemplateTargets.slotIndexes.sorted().map { "P\($0 + 1)" }
        guard !slots.isEmpty else {
            return "Select template targets with right-click; hold Shift to add"
        }
        return "Choose a template for \(slots.joined(separator: ", "))"
    }

    func headerActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .studioText(.labelBold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(StudioTheme.background)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
    }

    /// Neutral header chip (Routing). Distinct from the accent-filled
    /// `headerActionButton` so Capture/Perform read as the primary header pair.
    func headerSecondaryButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .studioText(.labelBold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(StudioTheme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    /// Capture header button (AC13/AC14). Toggles the history surface that
    /// replaces the tab content while the Patterns row stays visible. When
    /// open it reads as selected (accent fill).
    var captureButton: some View {
        Button {
            isCaptureOpen.toggle()
        } label: {
            Label("Capture", systemImage: "smallcircle.filled.circle")
                .studioText(.labelBold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isCaptureOpen ? StudioTheme.background : StudioTheme.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            isCaptureOpen ? accent : StudioTheme.subtleFill,
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                .stroke(isCaptureOpen ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .help("Capture: open the kit history surface to save a coordinated clip set")
        .accessibilityIdentifier("kit-capture")
        .accessibilityLabel("Capture kit history")
        .accessibilityValue(isCaptureOpen ? "Open" : "Closed")
    }

    /// Perform header button (AC13/AC22). Posts `.drumKitPerformRequested` with
    /// the group id; the coordinator (WorkspaceDetailView) enters the reused
    /// tracks-perform surface scoped to the kit's member tracks — no bespoke
    /// perform surface.
    var performButton: some View {
        Button {
            NotificationCenter.default.post(
                name: .drumKitPerformRequested,
                object: navigationState.groupID
            )
        } label: {
            Label("Perform", systemImage: "play.fill")
                .studioText(.labelBold)
        }
        .buttonStyle(.plain)
        .foregroundStyle(StudioTheme.background)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        .help("Perform: open the phrase perform UI scoped to the whole kit")
        .accessibilityIdentifier("kit-perform")
        .accessibilityLabel("Perform kit")
    }

    /// Fixed eight-indicator bar pager. Clips shorter than 128 steps keep the
    /// same compact footprint with unavailable bars dimmed. Legacy longer clips
    /// retain access through eight-bar banks selected by the chevrons.
    func barPager(_ model: DrumKitMatrixModel) -> some View {
        let longest = longestRowLength(model)
        let pageCount = barPageCount(longestRowLength: longest)
        let current = clampedPage(longestRowLength: longest)
        let indicators = DrumKitBarPaging.indicators(pageCount: pageCount, currentPage: current)
        let previousBank = DrumKitBarPaging.previousBankPage(currentPage: current)
        let nextBank = DrumKitBarPaging.nextBankPage(pageCount: pageCount, currentPage: current)

        return HStack(spacing: 6) {
            Text("BAR")
                .studioText(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)

            if pageCount > DrumKitBarPaging.indicatorCount {
                barBankButton(systemImage: "chevron.left", targetPage: previousBank)
            }

            HStack(spacing: 4) {
                ForEach(indicators, id: \.page) { indicator in
                    Button {
                        barPage = indicator.page
                    } label: {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barIndicatorFill(indicator.state))
                            .frame(width: 18, height: 7)
                    }
                    .buttonStyle(.plain)
                    .disabled(indicator.state == .unavailable)
                    .help(indicator.state == .unavailable
                        ? "Bar \(indicator.page + 1) is unavailable"
                        : "Show bar \(indicator.page + 1)")
                    .accessibilityLabel("Bar \(indicator.page + 1)")
                    .accessibilityValue(barIndicatorAccessibilityValue(indicator.state))
                }
            }

            if pageCount > DrumKitBarPaging.indicatorCount {
                barBankButton(systemImage: "chevron.right", targetPage: nextBank)
            }
        }
    }

    private func barIndicatorFill(_ state: DrumKitBarPaging.Indicator.State) -> Color {
        switch state {
        case .current:
            return accent
        case .available:
            return StudioTheme.neutral
        case .unavailable:
            return StudioTheme.disabledSubtleFill
        }
    }

    private func barIndicatorAccessibilityValue(_ state: DrumKitBarPaging.Indicator.State) -> String {
        switch state {
        case .current:
            return "Current"
        case .available:
            return "Available"
        case .unavailable:
            return "Unavailable"
        }
    }

    private func barBankButton(systemImage: String, targetPage: Int?) -> some View {
        Button {
            if let targetPage { barPage = targetPage }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .foregroundStyle(targetPage == nil ? StudioTheme.mutedText : StudioTheme.text)
        .disabled(targetPage == nil)
        .help(systemImage == "chevron.left" ? "Previous eight bars" : "Next eight bars")
    }
}
