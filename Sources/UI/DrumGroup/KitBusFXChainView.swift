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
            backgroundColor: StudioTheme.background,
            help: "Add FX"
        ) {
            onAddFX()
        }
    }

    private func insertRow(_ insert: MixerBusInsert) -> some View {
        InsertChainRow(
            title: insert.name,
            subtitle: insert.kind.summary,
            iconName: TrackFXChainView.iconName(for: insert.kind),
            accent: accent,
            isSelected: insert.id == selectedInsertID,
            isBypassed: !insert.isEnabled,
            iconSize: 12,
            iconWell: 24,
            iconCornerRadius: StudioMetrics.CornerRadius.chip,
            showsSelection: true,
            onSelect: { selectedInsertID = insert.id },
            onToggleBypass: { onSetBypassed(insert.id, $0) },
            onRemove: {
                let nextID = inserts.first(where: { $0.id != insert.id })?.id
                onRemove(insert.id)
                if selectedInsertID == insert.id {
                    selectedInsertID = nextID
                }
            }
        )
    }

    // MARK: - Per-insert editor (mirrors ScenesWorkspaceView.insertEditor)

    @ViewBuilder
    private var insertEditor: some View {
        if let insert = selectedInsert {
            VStack(alignment: .leading, spacing: 14) {
                kindEditor(insert)
            }
            .padding(StudioMetrics.Spacing.roomy)
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
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
    private func filterEditor(insert: MixerBusInsert, settings: MasterFilterSettings) -> some View {
        NativeInsertParameterEditor.Filter(
            settings: settings,
            accent: accent,
            onModeChange: { mode in
                session.updateMixerBusInsert(insert.id, busID: busID) { insert in
                    if case var .nativeFilter(settings) = insert.kind {
                        settings.mode = mode
                        insert.kind = .nativeFilter(settings)
                    }
                }
            },
            onCutoffChange: { setFilterCutoff(insertID: insert.id, value: $0) },
            onResonanceChange: { setFilterResonance(insertID: insert.id, value: $0) }
        )
    }

    private func bitcrusherEditor(insert: MixerBusInsert, settings: MasterBitcrusherSettings) -> some View {
        NativeInsertParameterEditor.Bitcrusher(
            settings: settings,
            accent: accent,
            onBitDepthChange: { bitDepth in
                session.updateMixerBusInsert(insert.id, busID: busID) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.bitDepth = bitDepth
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            },
            onRateChange: { value in
                session.updateMixerBusInsert(insert.id, busID: busID) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.sampleRateScale = value
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            },
            onDriveChange: { value in
                session.updateMixerBusInsert(insert.id, busID: busID) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.drive = value
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            }
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

}
