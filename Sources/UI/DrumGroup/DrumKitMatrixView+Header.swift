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
                        isPresentingTemplateChooser = true
                    }
                    .help("Apply a pattern template into pattern slot P\((model.groupSelectedSlotIndex ?? 0) + 1)")
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
        TrackPatternSlotPalette(
            selectedSlot: groupPatternSlotBinding(model),
            occupiedSlots: model.occupiedSlotIndexes,
            bypassState: .notApplicable,
            onBypassToggle: { _ in },
            accent: accent,
            destinationMode: isCaptureOpen && isSelectingCaptureSaveSlot
                ? TrackPatternSlotPalette.DestinationMode(
                    pendingReplaceSlot: historyTargetSlotIndex(model),
                    accent: accent
                )
                : nil,
            onDestinationSelect: { slotIndex in
                saveKitHistoryClipSet(model, slotIndex: slotIndex)
            }
        )
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

    /// Bar pager: one numbered chip per 16-step bar, shown only when
    /// the kit's longest row spans more than one bar. Selecting a page moves the
    /// visible 16-step window for every part row in lockstep. Locked grammar:
    /// a VALUE selector — the shared inset-track solid-thumb control INSIDE
    /// the well, with the BAR eyebrow beside the track (prototype 09).
    @ViewBuilder
    func barPager(_ model: DrumKitMatrixModel) -> some View {
        // Scan the rows for the longest length ONCE, then reuse it for both the
        // page count and the clamped current page.
        let longest = longestRowLength(model)
        let pageCount = barPageCount(longestRowLength: longest)
        if pageCount > 1 {
            let current = clampedPage(longestRowLength: longest)
            HStack(spacing: 6) {
                Text("BAR")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                StudioSegmentedControl(
                    title: nil,
                    selection: Binding(
                        get: { current },
                        set: { barPage = $0 }
                    ),
                    segments: (0..<pageCount).map { page in
                        let title = Self.barPageTitle(page)
                        return StudioSegment(
                            title: title,
                            value: page,
                            accessibilityLabel: "Bar \(title)",
                            help: "Show bar \(title)"
                        )
                    },
                    accent: accent,
                    layout: Self.matrixSelectorLayout(minWidth: 56)
                )
            }
        }
    }

    static func barPageTitle(_ page: Int) -> String {
        "\(page + 1)"
    }
}
