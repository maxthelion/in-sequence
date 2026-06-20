import SwiftUI

/// Kit-bus FX insert chain (AC23). Mirrors the Scenes FX grammar
/// (`ScenesWorkspaceView.sceneEditor`) so the two surfaces look identical:
///   - EMPTY: one full-width dashed "Add FX" tile (`StudioAddCard`).
///   - POPULATED: the insert list (drag-handle reorder, bypass + ✕ on one
///     line) with an "Add FX" tile BELOW the list, plus the per-insert editor
///     (native filter radial knobs + curve, bitcrusher) when an insert is
///     selected. No separate chooser pill at the top.
///
/// It edits the kit bus's `MixerBusInsert` chain (`MixerBusInsert` is a
/// typealias for `MasterBusInsert`, the same model Scenes uses) so the inserts
/// process the whole kit at once. Add/remove/reorder/bypass wiring goes through
/// the kit-bus session API (`addMixerBusInsert` etc.).
struct KitBusFXChainView: View {
    @Environment(SequencerDocumentSession.self) private var session

    let busID: UUID
    let inserts: [MixerBusInsert]
    let accent: Color
    let onAddFX: () -> Void
    let onRemove: (UUID) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onSetBypassed: (UUID, Bool) -> Void

    @State private var selectedInsertID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Empty kit bus = one full-width dashed "Add FX" tile (mirrors the
            // Scenes/tracks add grammar). The list + editor only appears once at
            // least one insert is present.
            if inserts.isEmpty {
                addFXTile(minHeight: 132)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        chainList
                            .frame(minWidth: 300, maxWidth: 380, alignment: .topLeading)
                        insertEditor
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        chainList
                        insertEditor
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { syncSelection() }
        .onChange(of: inserts.map(\.id)) { syncSelection() }
    }

    // MARK: - List + add tile (mirrors ScenesWorkspaceView.insertList)

    private var chainList: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A List with `.onMove` gives drag-to-reorder by handle, no arrows.
            List {
                ForEach(inserts) { insert in
                    insertRow(insert)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: onMove)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: listHeight)

            // Add-FX tile beneath the inserts (same dashed plus-tile grammar as
            // the empty state and the rest of the app).
            addFXTile(minHeight: 64)
        }
    }

    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 60
        let visibleRows = min(max(inserts.count, 1), 6)
        return CGFloat(visibleRows) * rowHeight
    }

    // Dashed full-width "Add FX" tile, reusing the same `StudioAddCard` grammar
    // as the Scenes FX section and the tracks navigator, tinted in-theme with
    // the kit accent. Opens the kit-bus add-FX picker sheet.
    private func addFXTile(minHeight: CGFloat) -> some View {
        StudioAddCard(
            label: "Add FX",
            accent: accent,
            minHeight: minHeight,
            help: "Add FX"
        ) {
            onAddFX()
        }
    }

    private func insertRow(_ insert: MixerBusInsert) -> some View {
        let isSelected = insert.id == selectedInsertID
        let icon = TrackFXChainView.iconName(for: insert.kind)
        return HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 18)
                .accessibilityLabel("Reorder \(insert.name)")

            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StudioTheme.background)
                .frame(width: 24, height: 24)
                .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(insert.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                Text(insert.kind.summary)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Bypass toggle + remove on the SAME line, no "Enabled" text.
            Toggle("Bypass \(insert.name)", isOn: bypassBinding(insert))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(StudioTheme.success)

            Button {
                let nextID = inserts.first(where: { $0.id != insert.id })?.id
                onRemove(insert.id)
                if selectedInsertID == insert.id {
                    selectedInsertID = nextID
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .buttonStyle(.plain)
            .help("Remove FX")
            .accessibilityLabel("Remove \(insert.name)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        // Colour identifies, it never floods (ux-canon rule 12): selection reads
        // from the accent outline, not a tinted row fill.
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(isSelected ? StudioTheme.cyan : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .opacity(insert.isEnabled ? 1 : 0.55)
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .onTapGesture {
            selectedInsertID = insert.id
        }
    }

    // MARK: - Per-insert editor (mirrors ScenesWorkspaceView.insertEditor)

    @ViewBuilder
    private var insertEditor: some View {
        if let insert = selectedInsert {
            VStack(alignment: .leading, spacing: 14) {
                kindEditor(insert)
            }
            .padding(StudioMetrics.Spacing.roomy)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        } else {
            EmptyView()
        }
    }

    private var selectedInsert: MixerBusInsert? {
        guard let selectedInsertID else { return inserts.first }
        return inserts.first(where: { $0.id == selectedInsertID }) ?? inserts.first
    }

    @ViewBuilder
    private func kindEditor(_ insert: MixerBusInsert) -> some View {
        switch insert.kind {
        case let .nativeFilter(settings):
            filterEditor(insert: insert, settings: settings)

        case let .nativeBitcrusher(settings):
            bitcrusherEditor(insert: insert, settings: settings)

        case .auEffect:
            auEffectSummary(insert)
        }
    }

    // Filter editor: radial cutoff/resonance knobs + response curve, mirroring
    // the Scenes filter editor (no wet/dry).
    @ViewBuilder
    private func filterEditor(insert: MixerBusInsert, settings: MasterFilterSettings) -> some View {
        let modeBinding = filterModeBinding(insertID: insert.id, settings: settings)
        VStack(alignment: .leading, spacing: 16) {
            filterModeSegmentedControl(selection: modeBinding)

            SceneFilterCurveView(
                mode: settings.mode,
                cutoffHz: settings.cutoffHz,
                resonance: settings.resonance,
                accent: accent
            )
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(StudioTheme.background.opacity(0.35), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )

            HStack(alignment: .top, spacing: 28) {
                StudioRotaryKnob(
                    title: "Cutoff",
                    value: settings.cutoffHz,
                    range: 20...20_000,
                    accent: accent,
                    size: 58,
                    format: { "\(Int($0.rounded())) Hz" },
                    onChange: { setFilterCutoff(insertID: insert.id, value: $0) },
                    onLiveChange: { setFilterCutoff(insertID: insert.id, value: $0) }
                )
                StudioRotaryKnob(
                    title: "Resonance",
                    value: settings.resonance,
                    range: 0...1,
                    accent: StudioTheme.amber,
                    size: 58,
                    format: { String(format: "%.2f", $0) },
                    onChange: { setFilterResonance(insertID: insert.id, value: $0) },
                    onLiveChange: { setFilterResonance(insertID: insert.id, value: $0) }
                )
                Spacer(minLength: 0)
            }
        }
    }

    // Studio segmented control for the filter type, matching the Scenes editor.
    private func filterModeSegmentedControl(selection: Binding<MasterFilterSettings.Mode>) -> some View {
        HStack(spacing: 4) {
            ForEach(MasterFilterSettings.Mode.allCases, id: \.self) { mode in
                filterModeChip(mode, selection: selection)
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

    private func filterModeChip(_ mode: MasterFilterSettings.Mode, selection: Binding<MasterFilterSettings.Mode>) -> some View {
        let isSelected = selection.wrappedValue == mode
        return Button {
            selection.wrappedValue = mode
        } label: {
            Text(mode.displayName)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text.opacity(0.78))
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 30)
                .padding(.horizontal, 10)
                .background(
                    isSelected ? StudioTheme.cyan : Color.clear,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter type \(mode.displayName)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    private func bitcrusherEditor(insert: MixerBusInsert, settings: MasterBitcrusherSettings) -> some View {
        Stepper("Bits: \(settings.bitDepth)", value: bitDepthBinding(insertID: insert.id, settings: settings), in: 4...16)
            .foregroundStyle(StudioTheme.text)
        sliderRow(
            title: "Rate",
            value: bitRateBinding(insertID: insert.id, settings: settings),
            range: 0.05...1,
            label: "\(Int((settings.sampleRateScale * 100).rounded()))%"
        )
        sliderRow(
            title: "Drive",
            value: bitDriveBinding(insertID: insert.id, settings: settings),
            range: 0...1,
            label: "\(Int((settings.drive * 100).rounded()))%"
        )
    }

    // AU inserts on the kit bus do not yet host an in-panel parameter editor
    // (the AU host is scoped to the master bus). Show the insert summary so the
    // editor pane is not empty, consistent with not inventing broken controls.
    private func auEffectSummary(_ insert: MixerBusInsert) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insert.name)
                .studioText(.bodyEmphasis)
                .foregroundStyle(StudioTheme.text)
            Text(insert.kind.summary)
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 82, alignment: .leading)
            Slider(value: value, in: range)
                .tint(accent)
            Text(label)
                .studioText(.eyebrow)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)
                .frame(width: 74, alignment: .trailing)
        }
    }

    // MARK: - Selection + bindings

    private func syncSelection() {
        if let selectedInsertID, inserts.contains(where: { $0.id == selectedInsertID }) {
            return
        }
        selectedInsertID = inserts.first?.id
    }

    private func bypassBinding(_ insert: MixerBusInsert) -> Binding<Bool> {
        Binding(
            get: { insert.isEnabled },
            set: { isActive in onSetBypassed(insert.id, !isActive) }
        )
    }

    private func filterModeBinding(insertID: UUID, settings: MasterFilterSettings) -> Binding<MasterFilterSettings.Mode> {
        Binding(
            get: { (filterSettings(insertID) ?? settings).mode },
            set: { mode in
                session.updateMixerBusInsert(insertID, busID: busID) { insert in
                    if case var .nativeFilter(settings) = insert.kind {
                        settings.mode = mode
                        insert.kind = .nativeFilter(settings)
                    }
                }
            }
        )
    }

    private func setFilterCutoff(insertID: UUID, value: Double) {
        session.updateMixerBusInsert(insertID, busID: busID) { insert in
            if case var .nativeFilter(settings) = insert.kind {
                settings.cutoffHz = value
                insert.kind = .nativeFilter(settings)
            }
        }
    }

    private func setFilterResonance(insertID: UUID, value: Double) {
        session.updateMixerBusInsert(insertID, busID: busID) { insert in
            if case var .nativeFilter(settings) = insert.kind {
                settings.resonance = value
                insert.kind = .nativeFilter(settings)
            }
        }
    }

    private func bitDepthBinding(insertID: UUID, settings: MasterBitcrusherSettings) -> Binding<Int> {
        Binding(
            get: { (bitcrusherSettings(insertID) ?? settings).bitDepth },
            set: { bitDepth in
                session.updateMixerBusInsert(insertID, busID: busID) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.bitDepth = bitDepth
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            }
        )
    }

    private func bitRateBinding(insertID: UUID, settings: MasterBitcrusherSettings) -> Binding<Double> {
        Binding(
            get: { (bitcrusherSettings(insertID) ?? settings).sampleRateScale },
            set: { value in
                session.updateMixerBusInsert(insertID, busID: busID) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.sampleRateScale = value
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            }
        )
    }

    private func bitDriveBinding(insertID: UUID, settings: MasterBitcrusherSettings) -> Binding<Double> {
        Binding(
            get: { (bitcrusherSettings(insertID) ?? settings).drive },
            set: { value in
                session.updateMixerBusInsert(insertID, busID: busID) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.drive = value
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            }
        )
    }

    private func filterSettings(_ insertID: UUID) -> MasterFilterSettings? {
        guard let insert = inserts.first(where: { $0.id == insertID }),
              case let .nativeFilter(settings) = insert.kind
        else { return nil }
        return settings
    }

    private func bitcrusherSettings(_ insertID: UUID) -> MasterBitcrusherSettings? {
        guard let insert = inserts.first(where: { $0.id == insertID }),
              case let .nativeBitcrusher(settings) = insert.kind
        else { return nil }
        return settings
    }
}
