import SwiftUI

// Header chrome and bar pager for the kit matrix: the title/back/routing/
// capture/perform header, its button styles, and the 16-step bar pager. Split
// out of DrumKitMatrixView.swift as an extension; zero behavior change.

extension DrumKitMatrixView {
    var header: some View {
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
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(accent)
                        .frame(width: 10, height: 10)
                    Text(model?.groupName ?? "Kit")
                        .studioText(.display)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text("\(model?.memberCountLabel ?? "No parts") · 16 steps/bar")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .frame(minWidth: 180, maxWidth: .infinity, alignment: .leading)

            headerSecondaryButton(title: "Routing", systemImage: "slider.horizontal.3") {
                isPresentingRoutingEditor = true
            }
            .help("Edit the kit's trigger routing and destinations")

            captureButton

            performButton
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.hoverFill), lineWidth: StudioMetrics.borderWidth)
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
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
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
            isCaptureOpen ? accent : Color.white.opacity(StudioOpacity.subtleFill),
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

    /// Bar pager: one button per 16-step bar (1–16, 17–32, …), shown only when
    /// the kit's longest row spans more than one bar. Selecting a page moves the
    /// visible 16-step window for every part row in lockstep.
    @ViewBuilder
    func barPager(_ model: DrumKitMatrixModel) -> some View {
        let pageCount = barPageCount(model)
        if pageCount > 1 {
            let current = clampedPage(model)
            HStack(spacing: 6) {
                Text("BAR")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                HStack(spacing: 4) {
                    ForEach(0..<pageCount, id: \.self) { page in
                        barPageButton(page, isSelected: page == current)
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
        }
    }

    func barPageButton(_ page: Int, isSelected: Bool) -> some View {
        let lower = page * Self.stepsPerBar + 1
        let upper = (page + 1) * Self.stepsPerBar
        let title = "\(lower)–\(upper)"

        return Button {
            barPage = page
        } label: {
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
        }
        .buttonStyle(.plain)
        .help("Show steps \(title)")
        .accessibilityLabel("Bar \(title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}
