import SwiftUI

/// Per-track FX insert chain UI (track-view IA, AC4 + AC5).
///
/// Each insert is one row with a drag handle (reorder — no up/down arrows), a
/// name + subtitle, and a bypass toggle + remove (✕) on the SAME line. Inserts
/// are added via a dashed full-width Add FX tile (not an "Insert" dropdown).
struct TrackFXChainView: View {
    @Environment(EngineController.self) private var engineController
    @Environment(SequencerDocumentSession.self) private var session

    let trackID: UUID
    let inserts: [TrackFXInsert]
    let accent: Color
    let onAddFX: () -> Void
    let onRemove: (UUID) -> Void
    let onMove: (IndexSet, Int) -> Void
    let onSetBypassed: (UUID, Bool) -> Void

    @State private var selectedInsertID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if inserts.isEmpty {
                emptyState
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
        .padding(StudioMetrics.Spacing.standard)
        .onAppear { syncSelection() }
        .onChange(of: inserts.map(\.id)) { syncSelection() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        StudioAddCard(
            label: "",
            accent: accent,
            minHeight: 132,
            backgroundColor: StudioTheme.background,
            help: "Add FX"
        ) {
            onAddFX()
        }
    }

    // MARK: - Populated chain

    private var chainList: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A List with `.onMove` gives the drag-to-reorder handle without
            // any up/down arrow buttons (AC4). Height is bounded so it sits
            // inside the FX tab body rather than expanding unbounded.
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

            StudioAddCard(
                label: "Add FX",
                accent: accent,
                minHeight: 64,
                backgroundColor: StudioTheme.background,
                help: "Add FX"
            ) {
                onAddFX()
            }
        }
    }

    private var listHeight: CGFloat {
        let rowHeight: CGFloat = 56
        let visibleRows = min(inserts.count, 5)
        return CGFloat(visibleRows) * rowHeight
    }

    private func insertRow(_ insert: TrackFXInsert) -> some View {
        InsertChainRow(
            title: insert.name,
            subtitle: insert.subtitle,
            iconName: Self.iconName(for: insert.kind),
            accent: accent,
            isSelected: insert.id == selectedInsertID,
            isBypassed: insert.bypassed,
            iconSize: 11,
            iconWell: 22,
            iconCornerRadius: StudioMetrics.CornerRadius.badge,
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

    @ViewBuilder
    private var insertEditor: some View {
        if let insert = selectedInsert {
            VStack(alignment: .leading, spacing: 14) {
                kindEditor(insert)
            }
            .padding(StudioMetrics.Spacing.roomy)
            .background(StudioTheme.background, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        } else {
            EmptyView()
        }
    }

    private var selectedInsert: TrackFXInsert? {
        guard let selectedInsertID else { return inserts.first }
        return inserts.first(where: { $0.id == selectedInsertID }) ?? inserts.first
    }

    @ViewBuilder
    private func kindEditor(_ insert: TrackFXInsert) -> some View {
        switch insert.kind {
        case let .nativeFilter(settings):
            filterEditor(insert: insert, settings: settings)

        case let .nativeBitcrusher(settings):
            bitcrusherEditor(insert: insert, settings: settings)

        case .auEffect:
            auEffectEditor(insert)
        }
    }

    private func filterEditor(insert: TrackFXInsert, settings: MasterFilterSettings) -> some View {
        NativeInsertParameterEditor.Filter(
            settings: settings,
            accent: accent,
            onModeChange: { mode in
                session.updateFXInsert(trackID: trackID, insertID: insert.id) { insert in
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

    private func bitcrusherEditor(insert: TrackFXInsert, settings: MasterBitcrusherSettings) -> some View {
        NativeInsertParameterEditor.Bitcrusher(
            settings: settings,
            accent: accent,
            onBitDepthChange: { bitDepth in
                session.updateFXInsert(trackID: trackID, insertID: insert.id) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.bitDepth = bitDepth
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            },
            onRateChange: { value in
                session.updateFXInsert(trackID: trackID, insertID: insert.id) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.sampleRateScale = value
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            },
            onDriveChange: { value in
                session.updateFXInsert(trackID: trackID, insertID: insert.id) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.drive = value
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            }
        )
    }

    private func auEffectEditor(_ insert: TrackFXInsert) -> some View {
        AUEffectEditorPanel(
            title: insert.name,
            subtitle: insert.kind.summary,
            accent: accent,
            prepare: {
                engineController.prepareTrackAUEffect(trackID: trackID, insertID: insert.id)
            },
            currentAudioUnit: {
                engineController.currentTrackAUEffect(trackID: trackID, insertID: insert.id)
            },
            parameterReadout: {
                engineController.trackAUEffectParameterReadout(trackID: trackID, insertID: insert.id)
            },
            openWindow: { audioUnit in
                AUWindowHost.shared.open(
                    for: .trackInsert(trackID: trackID, insertID: insert.id),
                    presenter: audioUnit,
                    title: insert.name
                ) { stateBlob in
                    session.setFXInsertAUEffectStateBlob(trackID: trackID, insertID: insert.id, stateBlob: stateBlob)
                }
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func syncSelection() {
        if let selectedInsertID, inserts.contains(where: { $0.id == selectedInsertID }) {
            return
        }
        selectedInsertID = inserts.first?.id
    }

    private func setFilterCutoff(insertID: UUID, value: Double) {
        session.updateFXInsert(trackID: trackID, insertID: insertID) { insert in
            if case var .nativeFilter(settings) = insert.kind {
                settings.cutoffHz = value
                insert.kind = .nativeFilter(settings)
            }
        }
    }

    private func setFilterResonance(insertID: UUID, value: Double) {
        session.updateFXInsert(trackID: trackID, insertID: insertID) { insert in
            if case var .nativeFilter(settings) = insert.kind {
                settings.resonance = value
                insert.kind = .nativeFilter(settings)
            }
        }
    }

    static func iconName(for kind: MasterBusInsertKind) -> String {
        switch kind {
        case .nativeFilter:
            return "line.3.horizontal.decrease.circle"
        case .nativeBitcrusher:
            return "waveform.path.ecg"
        case .auEffect:
            return "slider.horizontal.3"
        }
    }
}
