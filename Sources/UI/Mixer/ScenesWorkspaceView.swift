import SwiftUI

struct SceneMacroTargetPickerRequest: Identifiable, Equatable {
    let id = UUID()
    let sceneID: UUID
    let slotIndex: Int
}

struct AddInsertPickerRequest: Identifiable, Equatable {
    let id = UUID()
}

struct SceneDocumentEditSnapshot: Equatable {
    let scene: MasterBusScene
}

@MainActor
struct SceneDocumentEditCommandTarget {
    let session: SequencerDocumentSession
    let sceneID: UUID?
    let didPaste: (UUID) -> Void
    let clearSelection: () -> Void

    var target: DocumentEditCommandController.Target {
        .init(
            canCopy: { [self] in hasSceneTarget },
            canClear: { [self] in hasSceneTarget },
            isPasteCompatible: { [self] payload in
                hasSceneTarget
                    && payload.domain == .scenes
                    && payload.value(as: SceneDocumentEditSnapshot.self) != nil
            },
            copy: { [self] in
                guard let sceneID,
                      let scene = session.store.masterBus.scene(id: sceneID)
                else {
                    return nil
                }
                return .init(
                    domain: .scenes,
                    snapshot: SceneDocumentEditSnapshot(scene: scene)
                )
            },
            paste: { [self] payload in
                guard hasSceneTarget,
                      let snapshot = payload.value(as: SceneDocumentEditSnapshot.self)
                else {
                    return
                }
                didPaste(session.insertMasterBusSceneCopy(of: snapshot.scene))
            },
            clearSelection: { [self] in
                guard hasSceneTarget else { return }
                clearSelection()
            }
        )
    }

    private var hasSceneTarget: Bool {
        sceneID.flatMap { session.store.masterBus.scene(id: $0) } != nil
    }
}

enum SceneInsertOrdering {
    static func reordering(_ ids: [UUID], from source: IndexSet, to destination: Int) -> [UUID] {
        var reordered = ids
        reordered.move(fromOffsets: source, toOffset: destination)
        return reordered
    }
}

struct ScenePerformSlotPickerRequest: Identifiable, Equatable {
    enum Slot: String, Equatable {
        case a
        case b

        var shortTitle: String {
            switch self {
            case .a: "A"
            case .b: "B"
            }
        }

        var title: String {
            switch self {
            case .a: "Slot A"
            case .b: "Slot B"
            }
        }

        var accent: Color {
            StudioTheme.transportAccent
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
    var onOpenPhraseScenes: () -> Void = {}

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
        // Standard workspace surface inset (matches Tracks/Mixer/Track/Drum):
        // the borderless scene-browser panel had no outer padding, so it sat
        // tighter to the left/top than the other pages.
        .padding(StudioMetrics.Spacing.workspaceInset)
        .documentEditTarget(
            isActive: selectedSceneID != nil,
            revision: selectedSceneID
        ) {
            SceneDocumentEditCommandTarget(
                session: session,
                sceneID: selectedSceneID,
                didPaste: { newSceneID in
                    selectedSceneID = newSceneID
                    selectedInsertID = masterBus.scene(id: newSceneID)?.inserts.first?.id
                },
                clearSelection: clearSceneSelection
            ).target
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
        StudioPanel(title: "", accent: StudioTheme.transportAccent, showsHeader: false, contentPadding: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Text("SCENES")
                        .studioText(.microEmphasis)
                        .tracking(0.9)
                        .foregroundStyle(StudioTheme.transportAccent)

                    Spacer(minLength: 8)

                    Button {
                        session.requestScenePerform()
                        onOpenPhraseScenes()
                    } label: {
                        Label("Phrase Perform", systemImage: "square.split.2x2")
                            .studioText(.labelBold)
                            .foregroundStyle(StudioTheme.text)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                                    .stroke(StudioTheme.transportAccent, lineWidth: StudioMetrics.borderWidth)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Open phrase scene perform")
                }

                LazyVGrid(columns: sceneColumns, spacing: 12) {
                    ForEach(Array(masterBus.scenes.enumerated()), id: \.element.id) { index, scene in
                        sceneCard(scene, sceneNumber: index + 1)
                    }
                    addSceneCard
                }
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
            return
        }

        // QA: drive the add-FX (add-insert) picker sheet for capture coverage.
        switch command {
        case "addFX:open":
            addInsertPickerRequest = AddInsertPickerRequest()
            return
        case "addFX:close":
            addInsertPickerRequest = nil
            return
        default:
            break
        }

        // QA: select an insert by index in the currently selected scene so the
        // matching NativeInsertParameterEditor (e.g. Bitcrusher at index 1)
        // renders. The "content" fixture selects the filter (index 0) by default.
        if command.hasPrefix("selectInsert:"),
           let index = Int(command.dropFirst("selectInsert:".count)),
           selectedScene.inserts.indices.contains(index) {
            selectedInsertID = selectedScene.inserts[index].id
            return
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
            let (sceneID, firstInsertID) = populateVisualContentScene()
            selectedSceneID = sceneID
            selectedInsertID = firstInsertID
            session.setActiveMasterScene(sceneID)

        case "overflow":
            let (sceneID, firstInsertID) = populateVisualContentScene(insertCount: 8)
            selectedSceneID = sceneID
            selectedInsertID = firstInsertID
            session.setActiveMasterScene(sceneID)

        case "browse-content":
            // Same populated scene, but stay on the browser grid so the
            // per-card FX chips + duplicate/delete cluster are capturable.
            let (sceneID, _) = populateVisualContentScene()
            selectedSceneID = nil
            selectedInsertID = nil
            session.setActiveMasterScene(sceneID)

        default:
            break
        }
    }

    private func populateVisualContentScene(insertCount: Int = 2) -> (sceneID: UUID, firstInsertID: UUID) {
        let sceneID = ensureVisualScene(preferredIndex: 1, name: "Scene With Inserts")
        var filter = MasterBusInsert.filter()
        filter.name = "Visual Filter"
        var bitcrusher = MasterBusInsert.bitcrusher()
        bitcrusher.name = "Visual Crusher"
        let inserts = (0..<max(2, insertCount)).map { index -> MasterBusInsert in
            if index == 0 { return filter }
            if index == 1 { return bitcrusher }
            if index.isMultiple(of: 2) {
                var insert = MasterBusInsert.filter()
                insert.name = "Filter \(index / 2 + 1)"
                return insert
            }
            var insert = MasterBusInsert.bitcrusher()
            insert.name = "Crusher \(index / 2 + 1)"
            return insert
        }
        session.updateMasterBusScene(sceneID) { scene in
            scene.name = "Scene With Inserts"
            scene.inserts = inserts
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
        return (sceneID, filter.id)
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

    private func sceneCard(_ scene: MasterBusScene, sceneNumber: Int) -> some View {
        // The card body is tap-to-open (contentShape + tap gesture, matching
        // the Perform slot cards) rather than one big Button so the inline
        // duplicate/delete cluster stays independently clickable.
        let borderColor = sceneSlotBorderColor(scene.id)
        let borderWidth: CGFloat = sceneHasSlotMembership(scene.id) || scene.id == masterBus.activeSceneID
            ? 2
            : StudioMetrics.borderWidth

        return ZStack(alignment: .center) {
            Text("\(sceneNumber)")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(scene.id == masterBus.activeSceneID ? StudioTheme.transportAccent : StudioTheme.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            VStack {
                HStack {
                    Spacer(minLength: 0)
                    sceneSlotBadges(scene.id)
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 8) {
                    sceneCardFXChips(scene)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        StudioIconActionButton(
                            systemImage: "plus.square.on.square",
                            help: "New Scene From This"
                        ) {
                            duplicateScene(from: scene.id)
                        }
                        StudioIconActionButton(
                            systemImage: "trash",
                            isDisabled: masterBus.scenes.count <= 2,
                            help: "Delete Scene"
                        ) {
                            session.removeMasterBusScene(scene.id)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .center)
        .padding(StudioMetrics.Spacing.comfortable)
        // Colour identifies, it never floods (ux-canon rule 12): the card
        // body stays neutral; the active scene reads from the accent
        // outline and the solid slot badge.
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .onTapGesture {
            selectedSceneID = scene.id
            selectedInsertID = scene.inserts.first?.id
            session.setActiveMasterScene(scene.id)
        }
    }

    /// Cross-scene FX visibility: each browser card lists its actual insert
    /// names/icons so "see all the FX" is one scan over the scene grid, not a
    /// click into each scene. Long chains stay compact via a "+N more" line.
    @ViewBuilder
    private func sceneCardFXChips(_ scene: MasterBusScene) -> some View {
        if !scene.inserts.isEmpty {
            let visibleInserts = Array(scene.inserts.prefix(3))
            VStack(alignment: .leading, spacing: 4) {
                ForEach(visibleInserts) { insert in
                    HStack(spacing: 5) {
                        Image(systemName: iconName(for: insert.kind))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(StudioTheme.transportAccent)
                        Text(insert.name)
                            .studioText(.micro)
                            .foregroundStyle(StudioTheme.text)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(StudioTheme.subtleFill, in: Capsule())
                    .overlay(Capsule().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                }
                if scene.inserts.count > visibleInserts.count {
                    Text("+\(scene.inserts.count - visibleInserts.count) more")
                        .studioText(.micro)
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }
        }
    }

    /// "Create a new scene from one": whole-scene duplicate through the
    /// session seam (`duplicateMasterBusScene` → `addScene(copyFrom:)`), then
    /// land directly in the new scene's editor, mirroring `openNewScene()`.
    /// AB slot assignment is deliberately left untouched.
    private func duplicateScene(from sceneID: UUID) {
        guard let newSceneID = session.duplicateMasterBusScene(sceneID) else { return }
        selectedSceneID = newSceneID
        selectedInsertID = masterBus.scene(id: newSceneID)?.inserts.first?.id
    }

    @ViewBuilder
    private func sceneSlotBadges(_ sceneID: UUID) -> some View {
        HStack(spacing: 5) {
            if activeABSelection.sceneAID == sceneID {
                slotBadge("A", accent: ScenePerformSlotPickerRequest.Slot.a.accent)
            }
            if activeABSelection.sceneBID == sceneID {
                slotBadge("B", accent: ScenePerformSlotPickerRequest.Slot.b.accent)
            }
        }
    }

    private func sceneSlotBorderColor(_ sceneID: UUID) -> Color {
        let isA = activeABSelection.sceneAID == sceneID
        let isB = activeABSelection.sceneBID == sceneID
        if isA && isB { return StudioTheme.transportAccent }
        if isA { return ScenePerformSlotPickerRequest.Slot.a.accent }
        if isB { return ScenePerformSlotPickerRequest.Slot.b.accent }
        return sceneID == masterBus.activeSceneID ? StudioTheme.transportAccent : StudioTheme.border
    }

    private func sceneHasSlotMembership(_ sceneID: UUID) -> Bool {
        activeABSelection.sceneAID == sceneID || activeABSelection.sceneBID == sceneID
    }

    private func sceneNumber(for sceneID: UUID) -> Int? {
        masterBus.scenes.firstIndex { $0.id == sceneID }.map { $0 + 1 }
    }

    private func slotBadge(_ title: String, accent: Color) -> some View {
        Text(title)
            .studioText(.micro)
            .foregroundStyle(StudioTheme.background)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(accent, in: Capsule())
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
        CompactTrackDetailHeader(accent: StudioTheme.transportAccent) {
            Text("Scene \(sceneNumber(for: selectedScene.id) ?? 0)")
                .studioText(.title)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } trailing: {
            sceneClearOrRemoveButton
        }
    }

    private var sceneClearOrRemoveButton: some View {
        Button {
            clearOrRemoveSelectedScene()
        } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(StudioTheme.text)
                .frame(width: 34, height: 34)
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(masterBus.scenes.count > 2 ? "Remove this scene" : "Clear this scene")
        .accessibilityIdentifier("scene-editor-clear-remove")
        .accessibilityLabel(masterBus.scenes.count > 2 ? "Remove scene" : "Clear scene")
    }

    private func clearOrRemoveSelectedScene() {
        let sceneID = selectedScene.id
        if masterBus.scenes.count > 2 {
            session.removeMasterBusScene(sceneID)
            selectedSceneID = nil
            selectedInsertID = nil
            return
        }

        session.updateMasterBusScene(sceneID) { scene in
            scene.inserts = []
            scene.macroBindings = []
        }
        selectedInsertID = nil
    }

    private func clearSceneSelection() {
        selectedSceneID = nil
        selectedInsertID = nil
        auMacroSlotPickerRequest = nil
        sceneMacroTargetPickerRequest = nil
        scenePerformSlotPickerRequest = nil
        addInsertPickerRequest = nil
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
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .frame(height: insertListHeight)
            // Keep List's native scrolling and onMove semantics, but attach
            // the studio thumb to this fixed insert viewport only.
            .background(StudioAttachedVerticalScrollChrome())

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
    // Sound Source" tile, tinted with the app surface accent — never
    // the green success accent. It opens the add-FX picker sheet.
    private func addFXTile(minHeight: CGFloat) -> some View {
        StudioAddCard(
            label: "Add FX",
            accent: StudioTheme.transportAccent,
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
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.tile, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
    }

    private func insertRow(_ insert: MasterBusInsert) -> some View {
        InsertChainRow(
            title: insert.name,
            subtitle: insert.kind.summary,
            iconName: iconName(for: insert.kind),
            accent: StudioTheme.transportAccent,
            isSelected: insert.id == selectedInsertID,
            isBypassed: !insert.isEnabled,
            nameBinding: insertNameBinding(insert.id, fallback: insert.name),
            iconSize: 12,
            iconWell: 24,
            iconCornerRadius: StudioMetrics.CornerRadius.chip,
            showsSelection: true,
            onSelect: { selectedInsertID = insert.id },
            onToggleBypass: { isBypassed in
                session.updateMasterBusInsert(insert.id, in: selectedScene.id) { editing in
                    editing.isEnabled = !isBypassed
                }
            },
            onRemove: {
                session.removeMasterBusInsert(insert.id, from: selectedScene.id)
                selectedInsertID = selectedScene.inserts.first(where: { $0.id != insert.id })?.id
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
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
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
                    .foregroundStyle(StudioTheme.transportAccent)
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
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
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
                MacroSlotKnobDescriptor(
                    identity: $0.id.uuidString,
                    displayName: $0.name,
                    valueRange: $0.target.valueRange
                )
            },
            value: binding.flatMap { $0.value(in: selectedScene) },
            accent: StudioTheme.transportAccent,
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
                                .tint(StudioTheme.transportAccent)
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
                                .tint(StudioTheme.transportAccent)
                            }
                        }
                    }

                    if nativeTargets.isEmpty, auCandidates.isEmpty {
                        StudioPlaceholderTile(title: "No Assignable Targets", accent: StudioTheme.transportAccent)
                            .help("Add an insert to expose assignable targets")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                StudioPlaceholderTile(title: "Scene Missing", accent: StudioTheme.transportAccent)
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
            NativeInsertParameterEditor.Bitcrusher(
                settings: settings,
                accent: StudioTheme.transportAccent,
                onBitDepthChange: { bitDepthBinding(insertID: insert.id, settings: settings).wrappedValue = $0 },
                onRateChange: { bitRateBinding(insertID: insert.id, settings: settings).wrappedValue = $0 },
                onDriveChange: { bitDriveBinding(insertID: insert.id, settings: settings).wrappedValue = $0 }
            )

        case .auEffect:
            auEffectEditor(insert, scene: selectedScene)
        }
    }

    // MARK: - Filter editor (radial controls + curve viz, no wet/dry)

    private func filterEditor(insert: MasterBusInsert, settings: MasterFilterSettings) -> some View {
        let cutoffBinding = filterCutoffBinding(insertID: insert.id, settings: settings)
        let resonanceBinding = filterResonanceBinding(insertID: insert.id, settings: settings)
        let modeBinding = filterModeBinding(insertID: insert.id, settings: settings)

        return NativeInsertParameterEditor.Filter(
            settings: settings,
            accent: StudioTheme.transportAccent,
            onModeChange: { modeBinding.wrappedValue = $0 },
            onCutoffChange: { cutoffBinding.wrappedValue = $0 },
            onResonanceChange: { resonanceBinding.wrappedValue = $0 }
        )
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
        let ids = SceneInsertOrdering.reordering(
            selectedScene.inserts.map(\.id),
            from: source,
            to: destination
        )
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
