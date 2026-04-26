import SwiftUI

struct EndOfChainView: View {
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    var onBack: (() -> Void)? = nil

    @State private var selectedInsertID: UUID?
    @State private var saveAsName = ""

    private var masterBus: MasterBusState {
        session.store.masterBus
    }

    private var liveScene: MasterBusScene {
        masterBus.liveScene
    }

    private var selectedInsert: MasterBusInsert? {
        guard let selectedInsertID else { return liveScene.inserts.first }
        return liveScene.inserts.first(where: { $0.id == selectedInsertID }) ?? liveScene.inserts.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let selection = masterBus.abSelection {
                abControls(selection)
            }

            HStack(alignment: .top, spacing: 18) {
                insertList
                    .frame(minWidth: 360, maxWidth: 460, alignment: .topLeading)

                insertEditor
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            selectedInsertID = selectedInsert?.id
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if let onBack {
                Button(action: onBack) {
                    Label("Mixer", systemImage: "chevron.left")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(liveScene.name)
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                    if masterBus.hasUnsavedDraft {
                        Text("EDITED")
                            .studioText(.micro)
                            .tracking(0.8)
                            .foregroundStyle(StudioTheme.amber)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(StudioTheme.amber.opacity(StudioOpacity.softFill), in: Capsule())
                    }
                }
                Text("\(liveScene.inserts.count) inserts")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer()

            sceneMenu
            saveControls
            abToggle
        }
    }

    private var sceneMenu: some View {
        Menu {
            ForEach(masterBus.scenes) { scene in
                Button {
                    selectedInsertID = nil
                    session.setActiveMasterScene(scene.id)
                } label: {
                    Label(scene.name, systemImage: scene.id == masterBus.activeSceneID ? "checkmark" : "circle")
                }
            }
        } label: {
            Label("Scene", systemImage: "square.stack.3d.up")
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioTheme.violet)
    }

    private var saveControls: some View {
        HStack(spacing: 8) {
            Button {
                session.commitMasterBusDraft()
            } label: {
                Label("Save Scene", systemImage: "tray.and.arrow.down")
            }
            .disabled(!masterBus.hasUnsavedDraft)
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.cyan)

            Button {
                selectedInsertID = nil
                session.discardMasterBusDraft()
            } label: {
                Label("Revert", systemImage: "arrow.uturn.backward")
            }
            .disabled(!masterBus.hasUnsavedDraft)
            .buttonStyle(.bordered)
        }
    }

    private var abToggle: some View {
        Toggle(isOn: Binding(
            get: { masterBus.abSelection != nil },
            set: { enabled in
                if enabled {
                    enableABMode()
                } else {
                    session.setMasterABMode(nil)
                }
            }
        )) {
            Text("A/B")
                .studioText(.label)
        }
        .disabled(masterBus.scenes.count < 2)
        .toggleStyle(.switch)
        .tint(StudioTheme.amber)
    }

    private var insertList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("INSERTS")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                addInsertMenu
            }

            if liveScene.inserts.isEmpty {
                StudioPlaceholderTile(title: "Clean Chain", detail: "No inserts")
            } else {
                VStack(spacing: 8) {
                    ForEach(liveScene.inserts) { insert in
                        insertRow(insert)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("New scene", text: $saveAsName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                Button {
                    session.saveMasterBusDraft(as: saveAsName)
                    saveAsName = ""
                    selectedInsertID = nil
                } label: {
                    Label("Save As", systemImage: "plus.square.on.square")
                }
                .disabled(!masterBus.hasUnsavedDraft)
            }
        }
    }

    private var addInsertMenu: some View {
        Menu {
            Button {
                let insert = MasterBusInsert.filter()
                selectedInsertID = insert.id
                session.addMasterBusInsert(insert)
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }

            Button {
                let insert = MasterBusInsert.bitcrusher()
                selectedInsertID = insert.id
                session.addMasterBusInsert(insert)
            } label: {
                Label("Bitcrusher", systemImage: "waveform.path.ecg")
            }

            let effects = engineController.availableAudioEffects
            if effects.isEmpty {
                Button("No AU effects found") {}
                    .disabled(true)
            } else {
                Menu("AU Effect") {
                    ForEach(effects.prefix(16)) { effect in
                        Button(effect.displayName) {
                            let insert = MasterBusInsert.auEffect(effect)
                            selectedInsertID = insert.id
                            session.addMasterBusInsert(insert)
                        }
                    }
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioTheme.success)
    }

    private func insertRow(_ insert: MasterBusInsert) -> some View {
        Button {
            selectedInsertID = insert.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: iconName(for: insert.kind))
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(insert.name)
                        .studioText(.bodyEmphasis)
                        .foregroundStyle(StudioTheme.text)
                    Text(insert.kind.summary)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                }
                Spacer()
                Text(insert.isEnabled ? "ON" : "BYP")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(insert.isEnabled ? StudioTheme.success : StudioTheme.mutedText)
            }
            .padding(10)
            .background(rowFill(insert), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(insert.id == selectedInsert?.id ? StudioTheme.cyan : StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var insertEditor: some View {
        if let insert = selectedInsert {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(insert.name.uppercased())
                            .studioText(.bodyEmphasis)
                            .tracking(1)
                            .foregroundStyle(StudioTheme.text)
                        Text(insert.kind.summary)
                            .studioText(.label)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                    Spacer()
                    insertMoveButtons(insert)
                    Button(role: .destructive) {
                        session.removeMasterBusInsert(insert.id)
                        selectedInsertID = liveScene.inserts.first(where: { $0.id != insert.id })?.id
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }

                Toggle("Enabled", isOn: binding(for: insert.id, keyPath: \.isEnabled, fallback: insert.isEnabled))
                    .toggleStyle(.switch)
                    .tint(StudioTheme.success)

                sliderRow(
                    title: "Wet",
                    value: binding(for: insert.id, keyPath: \.wetDry, fallback: insert.wetDry),
                    range: 0...1,
                    label: "\(Int((insert.wetDry * 100).rounded()))%"
                )

                Divider()
                    .overlay(StudioTheme.border)

                kindEditor(insert)
            }
            .padding(16)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        } else {
            StudioPlaceholderTile(title: "No Insert Selected", detail: "Add an insert")
        }
    }

    private func insertMoveButtons(_ insert: MasterBusInsert) -> some View {
        HStack(spacing: 6) {
            Button {
                move(insert, by: -1)
            } label: {
                Image(systemName: "arrow.up")
            }
            .disabled(index(of: insert.id) == 0)

            Button {
                move(insert, by: 1)
            } label: {
                Image(systemName: "arrow.down")
            }
            .disabled(index(of: insert.id) == liveScene.inserts.count - 1)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private func kindEditor(_ insert: MasterBusInsert) -> some View {
        switch insert.kind {
        case let .nativeFilter(settings):
            Picker("Mode", selection: filterModeBinding(insertID: insert.id, settings: settings)) {
                Text("Low Pass").tag(MasterFilterSettings.Mode.lowPass)
                Text("High Pass").tag(MasterFilterSettings.Mode.highPass)
            }
            .pickerStyle(.segmented)

            sliderRow(
                title: "Cutoff",
                value: filterCutoffBinding(insertID: insert.id, settings: settings),
                range: 20...20_000,
                label: "\(Int(settings.cutoffHz.rounded())) Hz"
            )
            sliderRow(
                title: "Resonance",
                value: filterResonanceBinding(insertID: insert.id, settings: settings),
                range: 0...1,
                label: String(format: "%.2f", settings.resonance)
            )

        case let .nativeBitcrusher(settings):
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

        case .auEffect:
            HStack {
                Label("AU state", systemImage: "waveform")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Button {
                } label: {
                    Label("Open", systemImage: "slider.horizontal.3")
                }
                .disabled(true)
            }
        }
    }

    private func abControls(_ selection: MasterBusABSelection) -> some View {
        HStack(spacing: 14) {
            Picker("A", selection: sceneABinding(selection)) {
                ForEach(masterBus.scenes) { scene in
                    Text(scene.name).tag(scene.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Slider(value: Binding(
                get: { selection.crossfader },
                set: { session.setMasterCrossfader($0) }
            ), in: 0...1)
            .tint(StudioTheme.amber)

            Picker("B", selection: sceneBBinding(selection)) {
                ForEach(masterBus.scenes) { scene in
                    Text(scene.name).tag(scene.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)
        }
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, label: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 82, alignment: .leading)
            Slider(value: value, in: range)
                .tint(StudioTheme.cyan)
            Text(label)
                .studioText(.eyebrow)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.text)
                .frame(width: 74, alignment: .trailing)
        }
    }

    private func binding<Value>(for insertID: UUID, keyPath: WritableKeyPath<MasterBusInsert, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: {
                liveScene.inserts.first(where: { $0.id == insertID })?[keyPath: keyPath]
                    ?? fallback
            },
            set: { value in
                session.updateMasterBusInsert(insertID) { insert in
                    insert[keyPath: keyPath] = value
                }
            }
        )
    }

    private func filterModeBinding(insertID: UUID, settings: MasterFilterSettings) -> Binding<MasterFilterSettings.Mode> {
        Binding(
            get: { (settingsForFilter(insertID) ?? settings).mode },
            set: { mode in
                session.updateMasterBusInsert(insertID) { insert in
                    if case var .nativeFilter(settings) = insert.kind {
                        settings.mode = mode
                        insert.kind = .nativeFilter(settings)
                    }
                }
            }
        )
    }

    private func filterCutoffBinding(insertID: UUID, settings: MasterFilterSettings) -> Binding<Double> {
        Binding(
            get: { (settingsForFilter(insertID) ?? settings).cutoffHz },
            set: { cutoff in
                session.updateMasterBusInsert(insertID) { insert in
                    if case var .nativeFilter(settings) = insert.kind {
                        settings.cutoffHz = cutoff
                        insert.kind = .nativeFilter(settings)
                    }
                }
            }
        )
    }

    private func filterResonanceBinding(insertID: UUID, settings: MasterFilterSettings) -> Binding<Double> {
        Binding(
            get: { (settingsForFilter(insertID) ?? settings).resonance },
            set: { resonance in
                session.updateMasterBusInsert(insertID) { insert in
                    if case var .nativeFilter(settings) = insert.kind {
                        settings.resonance = resonance
                        insert.kind = .nativeFilter(settings)
                    }
                }
            }
        )
    }

    private func bitDepthBinding(insertID: UUID, settings: MasterBitcrusherSettings) -> Binding<Int> {
        Binding(
            get: { (settingsForBitcrusher(insertID) ?? settings).bitDepth },
            set: { bitDepth in
                session.updateMasterBusInsert(insertID) { insert in
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
            get: { (settingsForBitcrusher(insertID) ?? settings).sampleRateScale },
            set: { value in
                session.updateMasterBusInsert(insertID) { insert in
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
            get: { (settingsForBitcrusher(insertID) ?? settings).drive },
            set: { value in
                session.updateMasterBusInsert(insertID) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.drive = value
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            }
        )
    }

    private func settingsForFilter(_ insertID: UUID) -> MasterFilterSettings? {
        guard let insert = liveScene.inserts.first(where: { $0.id == insertID }),
              case let .nativeFilter(settings) = insert.kind
        else { return nil }
        return settings
    }

    private func settingsForBitcrusher(_ insertID: UUID) -> MasterBitcrusherSettings? {
        guard let insert = liveScene.inserts.first(where: { $0.id == insertID }),
              case let .nativeBitcrusher(settings) = insert.kind
        else { return nil }
        return settings
    }

    private func sceneABinding(_ selection: MasterBusABSelection) -> Binding<UUID> {
        Binding(
            get: { masterBus.abSelection?.sceneAID ?? selection.sceneAID },
            set: { sceneID in
                let current = masterBus.abSelection ?? selection
                session.setMasterABMode(MasterBusABSelection(sceneAID: sceneID, sceneBID: current.sceneBID, crossfader: current.crossfader))
            }
        )
    }

    private func sceneBBinding(_ selection: MasterBusABSelection) -> Binding<UUID> {
        Binding(
            get: { masterBus.abSelection?.sceneBID ?? selection.sceneBID },
            set: { sceneID in
                let current = masterBus.abSelection ?? selection
                session.setMasterABMode(MasterBusABSelection(sceneAID: current.sceneAID, sceneBID: sceneID, crossfader: current.crossfader))
            }
        )
    }

    private func enableABMode() {
        let sceneAID = masterBus.activeSceneID
        guard let sceneBID = masterBus.scenes.first(where: { $0.id != sceneAID })?.id else {
            return
        }
        session.setMasterABMode(MasterBusABSelection(sceneAID: sceneAID, sceneBID: sceneBID))
    }

    private func iconName(for kind: MasterBusInsertKind) -> String {
        switch kind {
        case .nativeFilter:
            return "line.3.horizontal.decrease.circle"
        case .nativeBitcrusher:
            return "waveform.path.ecg"
        case .auEffect:
            return "slider.horizontal.3"
        }
    }

    private func rowFill(_ insert: MasterBusInsert) -> Color {
        if insert.id == selectedInsert?.id {
            return StudioTheme.cyan.opacity(StudioOpacity.softFill)
        }
        return Color.white.opacity(StudioOpacity.subtleFill)
    }

    private func index(of insertID: UUID) -> Int {
        liveScene.inserts.firstIndex(where: { $0.id == insertID }) ?? 0
    }

    private func move(_ insert: MasterBusInsert, by delta: Int) {
        guard let current = liveScene.inserts.firstIndex(where: { $0.id == insert.id }) else { return }
        let next = max(0, min(liveScene.inserts.count - 1, current + delta))
        guard current != next else { return }
        var ids = liveScene.inserts.map(\.id)
        ids.remove(at: current)
        ids.insert(insert.id, at: next)
        session.reorderMasterBusInserts(ids)
    }
}
