import SwiftUI

struct SceneMacroTargetPickerRequest: Identifiable, Equatable {
    let id = UUID()
    let sceneID: UUID
    let slotIndex: Int
}

struct AddInsertPickerRequest: Identifiable, Equatable {
    let id = UUID()
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

    /// Top-level Scenes is scene management only. Scene perform now lives
    /// inside the selected phrase workspace.
    var mode: ScenesWorkspaceMode {
        .browseEdit
    }

    @State var selectedSceneID: UUID?
    @State var selectedInsertID: UUID?
    @State private var auMacroSlotPickerRequest: SceneAUMacroSlotPickerRequest?
    @State var sceneMacroTargetPickerRequest: SceneMacroTargetPickerRequest?
    @State var scenePerformSlotPickerRequest: ScenePerformSlotPickerRequest?
    @State private var addInsertPickerRequest: AddInsertPickerRequest?

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
            guard let command = notification.object as? String else { return }
            handleVisualCommand(command)
        }
        .onChange(of: resetToken) {
            // Navigation resets the page's selection only; the global mode is
            // session state — switching pages never changes mode underneath
            // you (wireframes §0).
            selectedSceneID = nil
            selectedInsertID = nil
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
        .sheet(item: $addInsertPickerRequest) { request in
            addInsertPickerSheet(request)
                .presentationBackground(.clear)
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
        StudioPanel(title: "", accent: StudioTheme.amber, showsHeader: false) {
            LazyVGrid(columns: sceneColumns, spacing: 12) {
                ForEach(masterBus.scenes) { scene in
                    sceneCard(scene)
                }
                addSceneCard
            }
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

    private func handleVisualCommand(_ command: String) {
        if command.hasPrefix("mode:") {
            // Legacy harness vocabulary is still accepted, but the top-level
            // Scenes page no longer switches into scene perform.
            session.workspaceMode = .setup
            return
        }

        if command.hasPrefix("fixture:") {
            applyVisualSceneEditorFixture(String(command.dropFirst("fixture:".count)))
        }
    }

    private func applyVisualSceneEditorFixture(_ rawFixture: String) {
        session.workspaceMode = .setup

        switch rawFixture {
        case "empty":
            let sceneID = ensureVisualScene(preferredIndex: 0, name: "Empty Scene")
            session.updateMasterBusScene(sceneID) { scene in
                scene.name = "Empty Scene"
                scene.inserts = []
                scene.macroBindings = []
            }
            selectedSceneID = sceneID
            selectedInsertID = nil
            session.setActiveMasterScene(sceneID)

        case "content":
            let sceneID = ensureVisualScene(preferredIndex: 1, name: "Scene With Inserts")
            var filter = MasterBusInsert.filter()
            filter.name = "Visual Filter"
            var bitcrusher = MasterBusInsert.bitcrusher()
            bitcrusher.name = "Visual Crusher"
            session.updateMasterBusScene(sceneID) { scene in
                scene.name = "Scene With Inserts"
                scene.inserts = [filter, bitcrusher]
                scene.macroBindings = [
                    MasterSceneMacroBinding(
                        slotIndex: 0,
                        name: "Cutoff",
                        target: .filterCutoff(insertID: filter.id),
                        authoredValue: 3_200
                    ),
                    MasterSceneMacroBinding(
                        slotIndex: 1,
                        name: "Drive",
                        target: .bitcrusherDrive(insertID: bitcrusher.id),
                        authoredValue: 0.35
                    )
                ]
            }
            selectedSceneID = sceneID
            selectedInsertID = filter.id
            session.setActiveMasterScene(sceneID)

        default:
            break
        }
    }

    private func ensureVisualScene(preferredIndex: Int, name: String) -> UUID {
        var scenes = masterBus.scenes
        while scenes.count <= preferredIndex {
            _ = session.addMasterBusScene(name: name)
            scenes = session.store.masterBus.scenes
        }
        let sceneID = scenes[preferredIndex].id
        session.setMasterSceneName(sceneID, name: name)
        return sceneID
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
                        .foregroundStyle(StudioTheme.background)
                        .frame(width: 30, height: 30)
                        .background(StudioTheme.amber, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
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
            // Colour identifies, it never floods (ux-canon rule 12): the card
            // body stays neutral; the active scene reads from the amber
            // outline and the solid slot badge.
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(scene.id == masterBus.activeSceneID ? StudioTheme.amber : StudioTheme.border, lineWidth: scene.id == masterBus.activeSceneID ? 2 : StudioMetrics.borderWidth)
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
            .foregroundStyle(StudioTheme.background)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(StudioTheme.amber, in: Capsule())
    }

    private var sceneEditor: some View {
        VStack(alignment: .leading, spacing: 18) {
            sceneEditorHeader

            // Empty scene = one full-width dashed "Add FX" tile (mirrors the
            // tracks/scenes add grammar). The two-column split (insert list |
            // editor) only appears once at least one insert is present.
            if selectedScene.inserts.isEmpty {
                addFXTile(minHeight: 132)
            } else {
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
                .studioText(.title)
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

    // Only rendered when at least one insert exists (empty scenes use the
    // full-width add-FX tile in `sceneEditor`). The add affordance is an
    // empty-with-plus tile BELOW the list, matching TrackFXChainView's
    // below-the-list add grammar (bug 135233).
    private var insertList: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A List with `.onMove` gives drag-to-reorder by handle, with no
            // up/down arrow buttons (bug 135534).
            List {
                ForEach(selectedScene.inserts) { insert in
                    insertRow(insert)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .onMove(perform: moveInserts)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .frame(height: insertListHeight)

            // Add-FX tile beneath the inserts (same dashed plus-tile grammar as
            // the empty state and the rest of the app).
            addFXTile(minHeight: 64)
        }
    }

    private var insertListHeight: CGFloat {
        let rowHeight: CGFloat = 60
        let visibleRows = min(max(selectedScene.inserts.count, 1), 6)
        return CGFloat(visibleRows) * rowHeight
    }

    // Dashed full-width "Add FX" tile (bugs 135118 + 135233): reuses the same
    // StudioAddCard grammar as the tracks navigator and the track-source "Add
    // Sound Source" tile, tinted in-theme with the Scenes accent (amber) — never
    // the green success accent. It opens the add-FX picker sheet.
    private func addFXTile(minHeight: CGFloat) -> some View {
        StudioAddCard(
            label: "Add FX",
            accent: StudioTheme.amber,
            minHeight: minHeight,
            help: "Add FX"
        ) {
            presentAddInsertPicker()
        }
    }

    private func presentAddInsertPicker() {
        addInsertPickerRequest = AddInsertPickerRequest()
    }

    private func addInsert(_ insert: MasterBusInsert) {
        selectedInsertID = insert.id
        session.addMasterBusInsert(insert, to: selectedScene.id)
        addInsertPickerRequest = nil
    }

    @ViewBuilder
    private func addInsertPickerSheet(_ request: AddInsertPickerRequest) -> some View {
        StudioModal(
            title: "Add FX",
            minWidth: 360,
            minHeight: 220,
            onClose: { addInsertPickerRequest = nil }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                addInsertOptionButton(title: "Filter", systemImage: "line.3.horizontal.decrease.circle") {
                    addInsert(MasterBusInsert.filter())
                }
                addInsertOptionButton(title: "Bitcrusher", systemImage: "waveform.path.ecg") {
                    addInsert(MasterBusInsert.bitcrusher())
                }

                Text("AU EFFECTS")
                    .studioText(.eyebrow)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.mutedText)
                    .padding(.top, 8)

                // Full, scrollable, searchable list — no longer capped at 16.
                AUEffectPickerList(effects: engineController.availableAudioEffects) { effect in
                    addInsertOptionButton(title: effect.displayName, systemImage: "slider.horizontal.3") {
                        addInsert(MasterBusInsert.auEffect(effect))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func addInsertOptionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
    }

    private func insertRow(_ insert: MasterBusInsert) -> some View {
        let isSelected = insert.id == selectedInsertID
        return HStack(spacing: 10) {
            // Drag handle for reorder (bug 135534: handle, never arrows).
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudioTheme.mutedText)
                .frame(width: 18)
                .accessibilityLabel("Reorder \(insert.name)")

            Image(systemName: iconName(for: insert.kind))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StudioTheme.background)
                .frame(width: 24, height: 24)
                .background(StudioTheme.amber, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                TextField("FX Name", text: insertNameBinding(insert.id, fallback: insert.name))
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .textFieldStyle(.plain)
                    .lineLimit(1)

                Text(insert.kind.summary)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Bypass toggle + remove on the SAME line, no "Enabled" text.
            Toggle("Bypass \(insert.name)", isOn: binding(for: insert.id, keyPath: \.isEnabled, fallback: insert.isEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(StudioTheme.success)

            Button {
                session.removeMasterBusInsert(insert.id, from: selectedScene.id)
                selectedInsertID = selectedScene.inserts.first(where: { $0.id != insert.id })?.id
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
        // Colour identifies, it never floods (ux-canon rule 12): selection
        // reads from the cyan outline, not a tinted row fill.
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
            // No FX selected / no FX yet: no helper text. The "+ FX" add control
            // already communicates the next action.
            EmptyView()
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
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
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
            filterEditor(insert: insert, settings: settings)

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

    // MARK: - Filter editor (radial controls + curve viz, no wet/dry)

    @ViewBuilder
    private func filterEditor(insert: MasterBusInsert, settings: MasterFilterSettings) -> some View {
        let cutoffBinding = filterCutoffBinding(insertID: insert.id, settings: settings)
        let resonanceBinding = filterResonanceBinding(insertID: insert.id, settings: settings)

        let modeBinding = filterModeBinding(insertID: insert.id, settings: settings)

        VStack(alignment: .leading, spacing: 16) {
            // Custom studio segmented control (bug 212622): mirrors the kit
            // tab-chip pattern, replacing the Aqua `.segmented` Picker.
            filterModeSegmentedControl(selection: modeBinding)

            SceneFilterCurveView(
                mode: settings.mode,
                cutoffHz: settings.cutoffHz,
                resonance: settings.resonance,
                accent: StudioTheme.cyan
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
                    accent: StudioTheme.cyan,
                    size: 58,
                    format: { "\(Int($0.rounded())) Hz" },
                    onChange: { cutoffBinding.wrappedValue = $0 },
                    onLiveChange: { cutoffBinding.wrappedValue = $0 }
                )
                StudioRotaryKnob(
                    title: "Resonance",
                    value: settings.resonance,
                    range: 0...1,
                    accent: StudioTheme.amber,
                    size: 58,
                    format: { String(format: "%.2f", $0) },
                    onChange: { resonanceBinding.wrappedValue = $0 },
                    onLiveChange: { resonanceBinding.wrappedValue = $0 }
                )
                Spacer(minLength: 0)
            }
        }
    }

    // Custom studio segmented control for the filter type, styled like the
    // drum-kit tab chips (flat, rounded, accent-filled selection).
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

    private func moveInserts(from source: IndexSet, to destination: Int) {
        var ids = selectedScene.inserts.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        session.reorderMasterBusInserts(ids, in: selectedScene.id)
    }

    private func macroTargets(for scene: MasterBusScene) -> [MasterSceneMacroTarget] {
        var targets: [MasterSceneMacroTarget] = []
        for insert in scene.inserts {
            // Wet/dry is fully removed from the filter (bug 135652): it is no
            // longer an assignable macro target.
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
