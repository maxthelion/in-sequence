import SwiftUI

// Matrix-tab content for the kit matrix: the group pattern row (link toggle,
// mixed/re-link badges, slot palette), the layer selector, mismatch/stale/empty
// states, and the matrix rows list + accordion toggle. Split out of
// DrumKitMatrixView.swift as an extension; zero behavior change.

extension DrumKitMatrixView {
    /// Group-level 1–16 pattern row, styled like a track's pattern selector.
    /// Selecting slot N fans the existing per-track pattern switch out to
    /// every member; a mixed state (no selected slot) renders when members
    /// diverge, and selecting any slot realigns them.
    func groupPatternRow(_ model: DrumKitMatrixModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("GROUP PATTERN")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)

                linkToggle(model)

                if model.isLinkBroken {
                    mixedBadge
                    reLinkButton
                } else if model.groupSelectedSlotIndex == nil && model.rows.count > 1 {
                    mixedBadge
                }

                Spacer(minLength: 0)
            }

            TrackPatternSlotPalette(
                selectedSlot: groupPatternSlotBinding(model),
                occupiedSlots: model.occupiedSlotIndexes,
                bypassState: .notApplicable,
                onBypassToggle: { _ in }
            )
        }
    }

    /// Explicit pattern-link toggle (AC17). Linked ⛓ gangs slot selection only;
    /// mute/fill/macros stay per-part. The pill reflects and flips the group's
    /// persisted `isPatternLinked`.
    func linkToggle(_ model: DrumKitMatrixModel) -> some View {
        let linked = model.isPatternLinked
        let title = linked ? "Linked" : "Unlinked"
        let symbol = linked ? "link" : "link.badge.plus"
        return Button {
            session.setDrumGroupPatternLinked(!linked, groupID: navigationState.groupID)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .studioText(.microEmphasis)
                    .tracking(0.6)
            }
            .foregroundStyle(linked ? StudioTheme.background : StudioTheme.text)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                linked ? accent : Color.white.opacity(StudioOpacity.subtleFill),
                in: Capsule()
            )
            .overlay(
                Capsule().stroke(linked ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .help(linked
            ? "Linked: selecting a group pattern switches every part to that slot. Mute, fill, and macros stay per-part."
            : "Unlinked: each part keeps its own pattern slot.")
        .accessibilityIdentifier("kit-link-toggle")
        .accessibilityLabel("Pattern linking")
        .accessibilityValue(linked ? "Linked" : "Unlinked")
    }

    var mixedBadge: some View {
        Text("MIXED")
            .studioText(.microEmphasis)
            .tracking(0.6)
            .foregroundStyle(StudioTheme.background)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(StudioTheme.amber, in: Capsule())
            .help("Members are on different pattern slots. Re-link realigns every part.")
    }

    /// One-click re-link (AC20). Re-gangs every member to the representative
    /// slot and restores the link; no modal, no pattern fork.
    var reLinkButton: some View {
        Button {
            session.reLinkDrumGroupPattern(groupID: navigationState.groupID)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.merge")
                    .font(.system(size: 10, weight: .bold))
                Text("Re-link")
                    .studioText(.microEmphasis)
                    .tracking(0.6)
            }
            .foregroundStyle(StudioTheme.background)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(accent, in: Capsule())
        }
        .buttonStyle(.plain)
        .help("Re-link: switch every part back to a shared pattern slot.")
        .accessibilityIdentifier("kit-relink")
        .accessibilityLabel("Re-link kit patterns")
    }

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
