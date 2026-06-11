import SwiftUI

struct SceneMacroTargetPickerRequest: Identifiable, Equatable {
    let id = UUID()
    let sceneID: UUID
    let slotIndex: Int
}

struct ScenePerformSlotPickerRequest: Identifiable, Equatable {
    enum Slot: String, Equatable {
        case a
        case b

        var title: String {
            switch self {
            case .a: "Slot A"
            case .b: "Slot B"
            }
        }
    }

    let id = UUID()
    let slot: Slot
}

struct ScenesWorkspaceView: View {
    @Binding var document: SeqAIDocument
    var resetToken: Int = 0
    @Environment(SequencerDocumentSession.self) var session
    @Environment(EngineController.self) var engineController

    @State var mode: ScenesWorkspaceMode = .browseEdit
    @State var selectedSceneID: UUID?
    @State var selectedInsertID: UUID?
    @State private var auMacroSlotPickerRequest: SceneAUMacroSlotPickerRequest?
    @State var sceneMacroTargetPickerRequest: SceneMacroTargetPickerRequest?
    @State var scenePerformSlotPickerRequest: ScenePerformSlotPickerRequest?

    private let sceneColumns = Array(
        repeating: GridItem(.flexible(minimum: 112, maximum: 190), spacing: 12),
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
        // No outer "Scenes" wrapper: the top-nav pill names the page and the
        // Perform toggle lives inside the panel header (ux-canon rules 1/10).
        Group {
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
        .onReceive(NotificationCenter.default.publisher(for: .scenesWorkspaceVisualCommand)) { notification in
            guard let command = notification.object as? String,
                  command.hasPrefix("mode:"),
                  let nextMode = ScenesWorkspaceMode(rawValue: String(command.dropFirst("mode:".count)))
            else { return }
            mode = nextMode
        }
        .onChange(of: resetToken) {
            selectedSceneID = nil
            selectedInsertID = nil
            mode = .browseEdit
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
        .sheet(item: $auMacroSlotPickerRequest) { request in
            sceneAUMacroSlotPickerSheet(request)
                .presentationBackground(.clear)
        }
        .sheet(item: $sceneMacroTargetPickerRequest) { request in
            sceneMacroTargetPickerSheet(request)
                .presentationBackground(.clear)
        }
        .sheet(item: $scenePerformSlotPickerRequest) { request in
            scenePerformSlotPickerSheet(request)
                .presentationBackground(.clear)
        }
    }

    var performToggleButton: some View {
        Button {
            mode = mode == .perform ? .browseEdit : .perform
        } label: {
            Label("Perform", systemImage: mode == .perform ? "record.circle.fill" : "record.circle")
                .studioText(.labelBold)
                .frame(minWidth: 96)
        }
        .buttonStyle(.borderedProminent)
        .tint(mode == .perform ? StudioTheme.amber : StudioTheme.cyan)
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
        StudioPanel(title: "", accent: StudioTheme.amber) {
            LazyVGrid(columns: sceneColumns, spacing: 12) {
                ForEach(masterBus.scenes) { scene in
                    sceneCard(scene)
                }
                addSceneCard
            }
        } accessory: {
            performToggleButton
        }
    }

    private var addSceneCard: some View {
        StudioAddCard(label: "Add Scene") {
            openNewScene()
        }
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
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .padding(StudioMetrics.Spacing.comfortable)
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
        VStack(alignment: .leading, spacing: 18) {
            sceneEditorHeader

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
        .padding(StudioMetrics.Spacing.loose)
        // Flat variant: solid panel value, no stroke or shadow.
        .background(StudioTheme.panelFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
    }

    private var sceneEditorHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            TextField("Scene Name", text: sceneNameBinding(selectedScene.id, fallback: selectedScene.name))
                .studioText(.display)
                .foregroundStyle(StudioTheme.text)
                .textFieldStyle(.plain)
                .frame(minWidth: 180, maxWidth: 420, alignment: .leading)
                .padding(.vertical, 4)
                .overlay(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(StudioTheme.cyan)
                        .frame(width: 36, height: 2)
                }

            Spacer()
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
        let isSelected = insert.id == selectedInsertID
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName(for: insert.kind))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 28, height: 28)
                    .background(StudioTheme.amber.opacity(StudioOpacity.selectedFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    TextField("Insert Name", text: insertNameBinding(insert.id, fallback: insert.name))
                        .studioText(.bodyEmphasis)
                        .foregroundStyle(StudioTheme.text)
                        .textFieldStyle(.plain)
                        .lineLimit(1)

                    Text(insert.kind.summary)
                        .studioText(.label)
                        .foregroundStyle(StudioTheme.mutedText)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                Toggle("Enabled", isOn: binding(for: insert.id, keyPath: \.isEnabled, fallback: insert.isEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(StudioTheme.success)
            }

            HStack(spacing: 6) {
                Text(insert.isEnabled ? "Enabled" : "Bypassed")
                    .studioText(.micro)
                    .tracking(0.8)
                    .foregroundStyle(insert.isEnabled ? StudioTheme.success : StudioTheme.mutedText)

                Spacer()

                insertMoveButtons(insert)

                Button(role: .destructive) {
                    session.removeMasterBusInsert(insert.id, from: selectedScene.id)
                    selectedInsertID = selectedScene.inserts.first(where: { $0.id != insert.id })?.id
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .help("Remove insert")
            }
        }
        .padding(StudioMetrics.Spacing.compact)
        .background(isSelected ? StudioTheme.cyan.opacity(StudioOpacity.softFill) : Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                .stroke(isSelected ? StudioTheme.cyan : StudioTheme.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
        .onTapGesture {
            selectedInsertID = insert.id
        }
    }

    @ViewBuilder
    private var insertEditor: some View {
        if let insert = selectedInsert {
            VStack(alignment: .leading, spacing: 14) {
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
            .padding(StudioMetrics.Spacing.roomy)
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(0..<MasterSceneMacroBinding.slotCount, id: \.self) { slotIndex in
                        macroSlot(slotIndex)
                            .frame(width: 68)
                    }
                }
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 12)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        }
    }

    private func macroSlot(_ slotIndex: Int) -> some View {
        let binding = selectedScene.macroBindings.first { $0.slotIndex == slotIndex }
        return MacroSlotKnob(
            slotIndex: slotIndex,
            descriptor: binding.map {
                MacroSlotKnobDescriptor(displayName: $0.name, valueRange: $0.target.valueRange)
            },
            value: binding.flatMap { $0.value(in: selectedScene) },
            accent: StudioTheme.cyan,
            onAssign: {
                sceneMacroTargetPickerRequest = SceneMacroTargetPickerRequest(sceneID: selectedScene.id, slotIndex: slotIndex)
            },
            onEdit: binding.map { _ in
                {
                    sceneMacroTargetPickerRequest = SceneMacroTargetPickerRequest(sceneID: selectedScene.id, slotIndex: slotIndex)
                }
            },
            onChange: { value in
                guard let binding else { return }
                session.setMasterSceneMacroValue(sceneID: selectedScene.id, macroID: binding.id, value: value)
            },
            onRemove: binding.map { binding in
                {
                    session.removeMasterSceneMacroBinding(binding.id, from: selectedScene.id)
                }
            }
        )
    }

    @ViewBuilder
    private func sceneMacroTargetPickerSheet(_ request: SceneMacroTargetPickerRequest) -> some View {
        StudioModal(
            title: "M\(request.slotIndex + 1)",
            minWidth: 420,
            minHeight: 260,
            onClose: { sceneMacroTargetPickerRequest = nil }
        ) {
            if let scene = masterBus.scene(id: request.sceneID) {
                VStack(alignment: .leading, spacing: 16) {
                    let nativeTargets = macroTargets(for: scene)
                    if !nativeTargets.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("INSERTS")
                                .studioText(.eyebrow)
                                .tracking(0.8)
                                .foregroundStyle(StudioTheme.mutedText)
                            ForEach(Array(nativeTargets.enumerated()), id: \.offset) { _, target in
                                Button {
                                    assignSceneMacroTarget(target, request: request, scene: scene)
                                } label: {
                                    Label(target.label(in: scene), systemImage: "slider.horizontal.3")
                                }
                                .buttonStyle(.bordered)
                                .tint(StudioTheme.cyan)
                            }
                        }
                    }

                    let auCandidates = auMacroInsertCandidates(in: scene)
                    if !auCandidates.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("AU PARAMETERS")
                                .studioText(.eyebrow)
                                .tracking(0.8)
                                .foregroundStyle(StudioTheme.mutedText)
                            ForEach(auCandidates) { insert in
                                Button {
                                    openAUMacroSlotPicker(insert, request: request)
                                } label: {
                                    Label(insert.name, systemImage: "slider.horizontal.3")
                                }
                                .buttonStyle(.bordered)
                                .tint(StudioTheme.cyan)
                            }
                        }
                    }

                    if nativeTargets.isEmpty, auCandidates.isEmpty {
                        StudioPlaceholderTile(title: "No Assignable Targets", detail: "Add an insert", accent: StudioTheme.cyan)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                StudioPlaceholderTile(title: "Scene Missing", detail: "Select another scene", accent: StudioTheme.cyan)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func assignSceneMacroTarget(
        _ target: MasterSceneMacroTarget,
        request: SceneMacroTargetPickerRequest,
        scene: MasterBusScene
    ) {
        let existing = scene.macroBindings.first { $0.slotIndex == request.slotIndex }
        let macro = MasterSceneMacroBinding(
            id: existing?.id ?? UUID(),
            slotIndex: request.slotIndex,
            target: target
        )
        session.upsertMasterSceneMacroBinding(macro, in: request.sceneID)
        sceneMacroTargetPickerRequest = nil
    }

    private func openAUMacroSlotPicker(_ insert: MasterBusInsert, request: SceneMacroTargetPickerRequest) {
        let sceneID = request.sceneID
        let slotIndex = request.slotIndex
        let insertID = insert.id
        sceneMacroTargetPickerRequest = nil
        Task { @MainActor in
            await Task.yield()
            prepareAndPresentAUMacroSlotPicker(slotIndex: slotIndex, sceneID: sceneID, insertID: insertID)
        }
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
            auEffectEditor(insert, scene: selectedScene)
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
        case let .auParameter(_, _, _, _, _, _, _, unit):
            let suffix = unit.map { " \($0)" } ?? ""
            return String(format: "%.2f", value) + suffix
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
        .controlSize(.small)
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
        var targets: [MasterSceneMacroTarget] = []
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

    private func auMacroInsertCandidates(in scene: MasterBusScene) -> [MasterBusInsert] {
        scene.inserts.filter { insert in
            if case .auEffect = insert.kind { return true }
            return false
        }
    }

    private func prepareAndPresentAUMacroSlotPicker(slotIndex: Int, sceneID: UUID, insertID: UUID) {
        engineController.prepareMasterAUEffect(insertID: insertID)
        auMacroSlotPickerRequest = SceneAUMacroSlotPickerRequest(
            sceneID: sceneID,
            insertID: insertID,
            slotIndex: slotIndex
        )
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
