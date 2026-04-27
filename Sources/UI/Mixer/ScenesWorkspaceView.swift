import SwiftUI

struct ScenesWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) var session
    @Environment(EngineController.self) var engineController

    @State private var mode: ScenesWorkspaceMode = .browseEdit
    @State private var selectedSceneID: UUID?
    @State private var selectedInsertID: UUID?

    private let sceneColumns = Array(
        repeating: GridItem(.flexible(minimum: 112, maximum: 190), spacing: 12),
        count: 8
    )

    private let macroColumns = Array(
        repeating: GridItem(.flexible(minimum: 120, maximum: 170), spacing: 10),
        count: 8
    )

    var masterBus: MasterBusState {
        session.store.masterBus
    }

    private var selectedScene: MasterBusScene {
        masterBus.scene(id: selectedSceneID ?? masterBus.activeSceneID) ?? masterBus.activeScene
    }

    var activeABSelection: MasterBusABSelection {
        if let selection = masterBus.abSelection {
            return selection
        }
        let scenes = masterBus.scenes
        return MasterBusABSelection(
            sceneAID: scenes.first?.id ?? MasterBusScene.sceneAID,
            sceneBID: scenes.dropFirst().first?.id ?? scenes.first?.id ?? MasterBusScene.sceneBID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if selectedSceneID == nil {
                header
            }

            switch mode {
            case .browseEdit:
                browseEdit
            case .perform:
                performView
            }
        }
        .onAppear {
            selectedInsertID = selectedSceneID.flatMap { masterBus.scene(id: $0)?.inserts.first?.id }
        }
        .onChange(of: masterBus.scenes.map(\.id)) {
            guard let selectedSceneID else {
                selectedInsertID = nil
                return
            }
            guard masterBus.scene(id: selectedSceneID) != nil else {
                self.selectedSceneID = nil
                selectedInsertID = nil
                return
            }
            if let selectedInsertID,
               !selectedScene.inserts.contains(where: { $0.id == selectedInsertID })
            {
                self.selectedInsertID = selectedScene.inserts.first?.id
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scenes")
                    .studioText(.display)
                    .foregroundStyle(StudioTheme.text)
                Text("\(masterBus.scenes.count) master bus scenes")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
            }

            Spacer()

            Picker("Mode", selection: $mode) {
                ForEach(ScenesWorkspaceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
        }
    }

    @ViewBuilder
    private var browseEdit: some View {
        if selectedSceneID == nil {
            sceneBrowser
        } else {
            sceneEditor
        }
    }

    private var sceneBrowser: some View {
        StudioPanel(title: "Scene Library", accent: StudioTheme.amber) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Text("\(masterBus.scenes.count) scenes")
                        .studioText(.labelBold)
                        .foregroundStyle(StudioTheme.mutedText)
                    Spacer()
                    addSceneButton
                }

                LazyVGrid(columns: sceneColumns, spacing: 12) {
                    ForEach(masterBus.scenes) { scene in
                        sceneCard(scene)
                    }
                    addSceneCard
                }
            }
        }
    }

    private var addSceneButton: some View {
        Button {
            openNewScene()
        } label: {
            Label("Add Scene", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .tint(StudioTheme.success)
    }

    private var addSceneCard: some View {
        Button {
            openNewScene()
        } label: {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(StudioTheme.success)
                    .frame(width: 34, height: 34)
                    .background(StudioTheme.success.opacity(StudioOpacity.selectedFill), in: Circle())
                Text("Add Scene")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.success.opacity(StudioOpacity.hoverFill), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            )
        }
        .buttonStyle(.plain)
    }

    private func openNewScene() {
        selectedSceneID = session.addMasterBusScene()
        selectedInsertID = nil
    }

    private func sceneCard(_ scene: MasterBusScene) -> some View {
        Button {
            selectedSceneID = scene.id
            selectedInsertID = scene.inserts.first?.id
            session.setActiveMasterScene(scene.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StudioTheme.text)
                        .frame(width: 30, height: 30)
                        .background(StudioTheme.amber.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
                    Spacer(minLength: 0)
                    sceneSlotBadges(scene.id)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(scene.name)
                        .studioText(.bodyEmphasis)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                    Text("\(scene.inserts.count) inserts - \(scene.macroBindings.count) macros")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }

                Text(String(format: "%.2f out", scene.outputGain))
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.amber)
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(12)
            .background(scene.id == masterBus.activeSceneID ? StudioTheme.amber.opacity(StudioOpacity.softFill) : Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(scene.id == masterBus.activeSceneID ? StudioTheme.amber : StudioTheme.border, lineWidth: scene.id == masterBus.activeSceneID ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sceneSlotBadges(_ sceneID: UUID) -> some View {
        HStack(spacing: 5) {
            if activeABSelection.sceneAID == sceneID {
                slotBadge("A")
            }
            if activeABSelection.sceneBID == sceneID {
                slotBadge("B")
            }
        }
    }

    private func slotBadge(_ title: String) -> some View {
        Text(title)
            .studioText(.micro)
            .foregroundStyle(StudioTheme.amber)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(StudioTheme.amber.opacity(StudioOpacity.hoverFill), in: Capsule())
    }

    private var sceneEditor: some View {
        StudioPanel(title: selectedScene.name, accent: StudioTheme.cyan) {
            VStack(alignment: .leading, spacing: 18) {
                editorToolbar

                HStack(spacing: 12) {
                    TextField("Scene Name", text: sceneNameBinding(selectedScene.id, fallback: selectedScene.name))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 320)

                    sliderRow(
                        title: "Output",
                        value: outputGainBinding(selectedScene.id, fallback: selectedScene.outputGain),
                        range: 0...1.5,
                        label: String(format: "%.2f", selectedScene.outputGain)
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        insertList
                            .frame(minWidth: 300, maxWidth: 380, alignment: .topLeading)
                        insertEditor
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: 18) {
                        insertList
                        insertEditor
                    }
                }

                macroAssignments
            }
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 8) {
            Button {
                selectedSceneID = nil
                selectedInsertID = nil
            } label: {
                Label("Scenes", systemImage: "chevron.left")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button {
                let createdID = session.duplicateMasterBusScene(selectedScene.id)
                selectedSceneID = createdID ?? selectedSceneID
                selectedInsertID = createdID.flatMap { session.store.masterBus.scene(id: $0)?.inserts.first?.id }
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive) {
                let removedID = selectedScene.id
                session.removeMasterBusScene(removedID)
                selectedSceneID = nil
                selectedInsertID = nil
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .disabled(masterBus.scenes.count <= 2)
        }
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

            if selectedScene.inserts.isEmpty {
                StudioPlaceholderTile(title: "Clean Chain", detail: "No inserts")
            } else {
                VStack(spacing: 8) {
                    ForEach(selectedScene.inserts) { insert in
                        insertRow(insert)
                    }
                }
            }
        }
    }

    private var addInsertMenu: some View {
        Menu {
            Button {
                let insert = MasterBusInsert.filter()
                selectedInsertID = insert.id
                session.addMasterBusInsert(insert, to: selectedScene.id)
            } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }

            Button {
                let insert = MasterBusInsert.bitcrusher()
                selectedInsertID = insert.id
                session.addMasterBusInsert(insert, to: selectedScene.id)
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
                            session.addMasterBusInsert(insert, to: selectedScene.id)
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
            .background(insert.id == selectedInsertID ? StudioTheme.cyan.opacity(StudioOpacity.softFill) : Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                    .stroke(insert.id == selectedInsertID ? StudioTheme.cyan : StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var insertEditor: some View {
        if let insert = selectedInsert {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    TextField("Insert Name", text: insertNameBinding(insert.id, fallback: insert.name))
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)

                    Spacer()
                    insertMoveButtons(insert)
                    Button(role: .destructive) {
                        session.removeMasterBusInsert(insert.id, from: selectedScene.id)
                        selectedInsertID = selectedScene.inserts.first(where: { $0.id != insert.id })?.id
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

    private var selectedInsert: MasterBusInsert? {
        guard let selectedInsertID else { return selectedScene.inserts.first }
        return selectedScene.inserts.first(where: { $0.id == selectedInsertID }) ?? selectedScene.inserts.first
    }

    private var macroAssignments: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("SCENE MACROS")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer()
                Text("\(selectedScene.macroBindings.count) / \(MasterSceneMacroBinding.slotCount)")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.cyan)
            }

            LazyVGrid(columns: macroColumns, spacing: 10) {
                ForEach(0..<MasterSceneMacroBinding.slotCount, id: \.self) { slotIndex in
                    macroSlot(slotIndex)
                }
            }
        }
    }

    private func macroSlot(_ slotIndex: Int) -> some View {
        let binding = selectedScene.macroBindings.first { $0.slotIndex == slotIndex }
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("M\(slotIndex + 1)")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.cyan)
                Spacer()
                if let binding {
                    Button {
                        session.removeMasterSceneMacroBinding(binding.id, from: selectedScene.id)
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(binding?.name ?? "Assign")
                .studioText(.bodyEmphasis)
                .foregroundStyle(binding == nil ? StudioTheme.mutedText : StudioTheme.text)
                .lineLimit(1)

            Menu {
                ForEach(Array(macroTargets(for: selectedScene).enumerated()), id: \.offset) { _, target in
                    Button(target.label(in: selectedScene)) {
                        let macro = MasterSceneMacroBinding(
                            id: binding?.id ?? UUID(),
                            slotIndex: slotIndex,
                            target: target
                        )
                        session.upsertMasterSceneMacroBinding(macro, in: selectedScene.id)
                    }
                }
            } label: {
                Label(binding == nil ? "Assign" : "Change", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)

            if let binding,
               let value = binding.value(in: selectedScene)
            {
                Slider(
                    value: macroValueBinding(binding, fallback: value),
                    in: binding.target.valueRange
                )
                .tint(StudioTheme.cyan)

                Text(sceneMacroValueLabel(value, target: binding.target))
                    .studioText(.micro)
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(binding == nil ? StudioTheme.border : StudioTheme.cyan.opacity(StudioOpacity.mediumStroke), lineWidth: 1)
        )
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
            Label("AU parameter editing is not available yet", systemImage: "slider.horizontal.3")
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
        }
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

    private func sceneNameBinding(_ sceneID: UUID, fallback: String) -> Binding<String> {
        Binding(
            get: { masterBus.scene(id: sceneID)?.name ?? fallback },
            set: { session.setMasterSceneName(sceneID, name: $0) }
        )
    }

    private func outputGainBinding(_ sceneID: UUID, fallback: Double) -> Binding<Double> {
        Binding(
            get: { masterBus.scene(id: sceneID)?.outputGain ?? fallback },
            set: { session.setMasterSceneOutputGain(sceneID, value: $0) }
        )
    }

    private func macroValueBinding(_ binding: MasterSceneMacroBinding, fallback: Double) -> Binding<Double> {
        let sceneID = selectedScene.id
        let macroID = binding.id
        return Binding(
            get: {
                guard let scene = masterBus.scene(id: sceneID),
                      let binding = scene.macroBindings.first(where: { $0.id == macroID }),
                      let value = binding.value(in: scene)
                else {
                    return fallback
                }
                return value
            },
            set: { value in
                session.setMasterSceneMacroValue(sceneID: sceneID, macroID: macroID, value: value)
            }
        )
    }

    private func sceneMacroValueLabel(_ value: Double, target: MasterSceneMacroTarget) -> String {
        switch target {
        case .filterCutoff:
            return "\(Int(value.rounded())) Hz"
        case .outputGain:
            return String(format: "%.2f", value)
        default:
            return "\(Int((value * 100).rounded()))%"
        }
    }

    private func insertNameBinding(_ insertID: UUID, fallback: String) -> Binding<String> {
        Binding(
            get: { selectedScene.inserts.first(where: { $0.id == insertID })?.name ?? fallback },
            set: { name in
                session.updateMasterBusInsert(insertID, in: selectedScene.id) { insert in
                    insert.name = name
                }
            }
        )
    }

    private func binding<Value>(
        for insertID: UUID,
        keyPath: WritableKeyPath<MasterBusInsert, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: {
                selectedScene.inserts.first(where: { $0.id == insertID })?[keyPath: keyPath]
                    ?? fallback
            },
            set: { value in
                session.updateMasterBusInsert(insertID, in: selectedScene.id) { insert in
                    insert[keyPath: keyPath] = value
                }
            }
        )
    }

    private func filterModeBinding(insertID: UUID, settings: MasterFilterSettings) -> Binding<MasterFilterSettings.Mode> {
        Binding(
            get: { (settingsForFilter(insertID) ?? settings).mode },
            set: { mode in
                session.updateMasterBusInsert(insertID, in: selectedScene.id) { insert in
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
                session.updateMasterBusInsert(insertID, in: selectedScene.id) { insert in
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
                session.updateMasterBusInsert(insertID, in: selectedScene.id) { insert in
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
                session.updateMasterBusInsert(insertID, in: selectedScene.id) { insert in
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
                session.updateMasterBusInsert(insertID, in: selectedScene.id) { insert in
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
                session.updateMasterBusInsert(insertID, in: selectedScene.id) { insert in
                    if case var .nativeBitcrusher(settings) = insert.kind {
                        settings.drive = value
                        insert.kind = .nativeBitcrusher(settings)
                    }
                }
            }
        )
    }

    private func settingsForFilter(_ insertID: UUID) -> MasterFilterSettings? {
        guard let insert = selectedScene.inserts.first(where: { $0.id == insertID }),
              case let .nativeFilter(settings) = insert.kind
        else { return nil }
        return settings
    }

    private func settingsForBitcrusher(_ insertID: UUID) -> MasterBitcrusherSettings? {
        guard let insert = selectedScene.inserts.first(where: { $0.id == insertID }),
              case let .nativeBitcrusher(settings) = insert.kind
        else { return nil }
        return settings
    }

    func sceneABinding(_ selection: MasterBusABSelection) -> Binding<UUID> {
        Binding(
            get: { masterBus.abSelection?.sceneAID ?? selection.sceneAID },
            set: { sceneID in
                engineController.clearMasterBusPerformanceOverlay()
                let current = masterBus.abSelection ?? selection
                let sceneBID = current.sceneBID == sceneID ? current.sceneAID : current.sceneBID
                session.setMasterABMode(MasterBusABSelection(sceneAID: sceneID, sceneBID: sceneBID, crossfader: current.crossfader))
            }
        )
    }

    func sceneBBinding(_ selection: MasterBusABSelection) -> Binding<UUID> {
        Binding(
            get: { masterBus.abSelection?.sceneBID ?? selection.sceneBID },
            set: { sceneID in
                engineController.clearMasterBusPerformanceOverlay()
                let current = masterBus.abSelection ?? selection
                let sceneAID = current.sceneAID == sceneID ? current.sceneBID : current.sceneAID
                session.setMasterABMode(MasterBusABSelection(sceneAID: sceneAID, sceneBID: sceneID, crossfader: current.crossfader))
            }
        )
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
            .disabled(index(of: insert.id) == selectedScene.inserts.count - 1)
        }
        .buttonStyle(.bordered)
    }

    private func move(_ insert: MasterBusInsert, by delta: Int) {
        guard let current = selectedScene.inserts.firstIndex(where: { $0.id == insert.id }) else { return }
        let next = max(0, min(selectedScene.inserts.count - 1, current + delta))
        guard current != next else { return }
        var ids = selectedScene.inserts.map(\.id)
        ids.remove(at: current)
        ids.insert(insert.id, at: next)
        session.reorderMasterBusInserts(ids, in: selectedScene.id)
    }

    private func index(of insertID: UUID) -> Int {
        selectedScene.inserts.firstIndex(where: { $0.id == insertID }) ?? 0
    }

    private func macroTargets(for scene: MasterBusScene) -> [MasterSceneMacroTarget] {
        var targets: [MasterSceneMacroTarget] = [.outputGain]
        for insert in scene.inserts {
            targets.append(.insertWetDry(insertID: insert.id))
            switch insert.kind {
            case .nativeFilter:
                targets.append(.filterCutoff(insertID: insert.id))
                targets.append(.filterResonance(insertID: insert.id))
            case .nativeBitcrusher:
                targets.append(.bitcrusherRate(insertID: insert.id))
                targets.append(.bitcrusherDrive(insertID: insert.id))
            case .auEffect:
                break
            }
        }
        return targets
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

}
