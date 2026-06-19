import SwiftUI

struct PhraseWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Binding private var visualControlsOpenIndex: Int?
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    @State private var selectedLayerID = "pattern"
    @State private var editingCellTarget: PhraseCellEditorTarget?
    @State private var trackPage = 0
    @State private var phraseTab: PhraseWorkspaceTab = .layers
    @State private var performanceLayerSelection = PerformanceLayerSelectionState()
    @State private var isPresentingPerformanceLayerSelection = false
    @State private var phraseCellTool: PhraseCellTool = .value
    @State private var globalApplyScope = TrackPerformSelectionState()
    @State private var isPresentingGlobalApplyTrackSelector = false
    @State private var phraseSceneSlotPickerRequest: ScenePerformSlotPickerRequest?
    @State private var isPresentingPhraseCapture = false
    @State private var phraseLatchMode: TrackPerformLatchMode = .momentary
    @State private var phraseLatchLengthBars: Int?
    @State private var scalarDragBase: (phraseID: UUID, trackID: UUID, value: Double)?

    private let phraseColumnWidth: CGFloat = 118
    private let trackColumnWidth: CGFloat = 126
    private let actionColumnWidth: CGFloat = 100
    private let matrixGutterWidth = PhraseMatrixLayoutPresentation.matrixGutterWidth
    private let gridSpacing: CGFloat = 10
    private let trackPageSize = PhraseMatrixLayoutPresentation.trackPageSize
    private let phraseLatchLengthOptions: [Int?] = [nil, 1, 2, 4, 8]

    init(
        document: Binding<SeqAIDocument>,
        visualControlsOpenIndex: Binding<Int?> = .constant(nil)
    ) {
        self._document = document
        self._visualControlsOpenIndex = visualControlsOpenIndex
    }

    private var phrases: [PhraseModel] { session.store.phrases }
    private var tracks: [StepSequenceTrack] { session.store.tracks }
    private var layers: [PhraseLayerDefinition] { session.store.layers }
    private var matrixSelectableLayers: [PhraseLayerDefinition] {
        let selectableLayers = PhraseLayerSelectorPresentation.selectableLayers(from: layers)
        return selectableLayers.isEmpty ? layers : selectableLayers
    }
    private var selectedTrack: StepSequenceTrack { session.store.selectedTrack }

    private var selectedLayer: PhraseLayerDefinition {
        matrixSelectableLayers.first { $0.id == selectedLayerID }
            ?? matrixSelectableLayers.first
            ?? PhraseLayerDefinition.defaultSet(for: tracks).first!
    }

    private var selectedLayerIndex: Int {
        matrixSelectableLayers.firstIndex(where: { $0.id == selectedLayer.id }) ?? 0
    }

    private var activeMatrixLayer: PhraseLayerDefinition? {
        guard let layerID = performanceLayerSelection.mode.phraseLayerID else {
            return nil
        }

        return matrixSelectableLayers.first { $0.id == layerID }
            ?? layers.first { $0.id == layerID }
    }

    private var activeLayerAccent: Color {
        activeMatrixLayer.map { layerAccent($0.id) } ?? performanceLayerSelection.mode.selectorAccent
    }

    private var trackPageCount: Int {
        matrixLayout.pageCount
    }

    private var matrixLayout: PhraseMatrixLayoutPresentation {
        PhraseMatrixLayoutPresentation(trackCount: tracks.count, pageIndex: trackPage)
    }

    private var trackGridWidth: CGFloat {
        let columnCount = CGFloat(trackPageSize)
        return columnCount * trackColumnWidth + max(0, columnCount - 1) * gridSpacing
    }

    private var visibleTrackSlots: [StepSequenceTrack?] {
        let startIndex = min(trackPage * trackPageSize, tracks.count)
        let pagedTracks = Array(tracks.dropFirst(startIndex).prefix(trackPageSize))
        return pagedTracks.map(Optional.some) + Array(repeating: nil, count: max(0, trackPageSize - pagedTracks.count))
    }

    private var selectedPhraseForEditing: PhraseModel {
        session.phraseWithPerformOverlay(session.store.selectedPhrase)
    }

    var body: some View {
        // The top-nav pill already names this page; the panel renders no
        // header of its own (ux-canon rule 1).
        StudioPanel(
            title: "Phrase Matrix",
            accent: activeLayerAccent,
            showsHeader: false
        ) {
            VStack(alignment: .leading, spacing: 16) {
                phrasePerformanceShell
                phraseTabBar
                switch phraseTab {
                case .layers:
                    layerBar
                    if isPresentingPerformanceLayerSelection {
                        performanceLayerSelectionSurface
                    } else {
                        matrix
                    }
                case .scenes:
                    phraseScenesSurface
                case .globalApply:
                    globalApplySurface
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .sheet(item: $editingCellTarget) { target in
            PhraseCellEditorSheet(
                target: target,
                accent: layerAccent(target.layerID)
            )
            .presentationBackground(.clear)
        }
        .sheet(isPresented: $isPresentingPhraseCapture) {
            PhrasePerformCaptureSheet(
                phrases: session.store.phrases,
                basisPhraseID: session.phrasePerformOverlay.basisPhraseID,
                stagedCellCount: session.phrasePerformOverlay.stagedChangeCount,
                onCaptureExisting: { phraseID in
                    _ = session.capturePhrasePerformOverlay(to: phraseID)
                    isPresentingPhraseCapture = false
                },
                onCaptureNew: {
                    _ = session.capturePhrasePerformOverlayToNewPhrase()
                    isPresentingPhraseCapture = false
                },
                onCancel: {
                    isPresentingPhraseCapture = false
                }
            )
            .presentationBackground(.clear)
        }
        .sheet(item: $phraseSceneSlotPickerRequest) { request in
            phraseSceneSlotPickerSheet(request)
                .presentationBackground(.clear)
        }
        .onAppear {
            reconcileSelectedLayer()
            clampTrackPage()
            applyVisualControlsOpenIndex()
            for command in VisualScenarioCommandRunner.drainPendingPhraseMatrixCommands() {
                applyMatrixVisualCommand(command)
            }
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onDisappear {
            postRenderedMatrixVisualState(isVisible: false)
        }
        .onChange(of: visualControlsOpenIndex) {
            applyVisualControlsOpenIndex()
        }
        .onChange(of: session.store.selectedTrackID) {
            syncTrackPageToSelection()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: tracks.count) {
            clampTrackPage()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: trackPage) {
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: phrases.map(\.id)) {
            dismissInvalidEditorTarget()
            applyVisualControlsOpenIndex()
        }
        .onChange(of: tracks.map(\.id)) {
            dismissInvalidEditorTarget()
        }
        .onChange(of: layers.map(\.id)) {
            dismissInvalidEditorTarget()
            reconcileSelectedLayer()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: selectedLayerID) {
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: performanceLayerSelection.mode) {
            if let layerID = performanceLayerSelection.mode.phraseLayerID,
               matrixSelectableLayers.contains(where: { $0.id == layerID }) {
                selectedLayerID = layerID
            }
            performanceLayerSelection.reconcileVariant()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: performanceLayerSelection.variantLabel) {
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .phraseMatrixVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            // Receiving live proves this view is mounted; the pending copy
            // would otherwise replay stale on a later remount.
            VisualScenarioCommandRunner.pendingPhraseMatrixCommands = []
            applyMatrixVisualCommand(command)
        }
    }

    private var phrasePerformanceShell: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(phraseShellTitle)
                    .studioText(.title)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)

                Text(phraseShellDetail)
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            phrasePerformToggle
            phraseDirtyPill
            phraseLatchTimingControls
            phraseCaptureActions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(phraseShellAccent.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("phrase-performance-shell")
    }

    private var phraseShellTitle: String {
        let phraseName = session.store.selectedPhrase.name
        return session.workspaceMode == .perform ? "\(phraseName) / Perform Copy" : "\(phraseName) / Edit Baseline"
    }

    private var phraseShellDetail: String {
        if session.workspaceMode == .perform {
            return "Changes stage in a temporary phrase copy. Capture chooses where that modified phrase is saved."
        }
        return "Perform is off. Phrase edits write to the baseline; Capture and Discard stay visible but inactive."
    }

    private var phraseShellAccent: Color {
        session.workspaceMode == .perform ? StudioTheme.amber : StudioTheme.violet
    }

    private var phrasePerformToggle: some View {
        Button {
            session.workspaceMode = session.workspaceMode == .perform ? .setup : .perform
        } label: {
            Text(session.workspaceMode == .perform ? "Perform On" : "Perform Off")
                .studioText(.labelBold)
                .foregroundStyle(session.workspaceMode == .perform ? StudioTheme.background : StudioTheme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(session.workspaceMode == .perform ? StudioTheme.amber : Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(phraseShellAccent, lineWidth: StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("phrase-perform-toggle")
        .help(session.workspaceMode == .perform ? "Turn off phrase perform copy editing" : "Edit a temporary phrase copy during performance")
    }

    private var phraseDirtyPill: some View {
        let hasActivePerformChanges = session.workspaceMode == .perform && session.phrasePerformOverlay.isDirty
        return Text(phraseDirtyText)
            .studioText(.microEmphasis)
            .tracking(0.8)
            .foregroundStyle(hasActivePerformChanges ? StudioTheme.background : StudioTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(hasActivePerformChanges ? StudioTheme.amber : StudioTheme.inset, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(hasActivePerformChanges ? StudioTheme.amber : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .accessibilityIdentifier("phrase-perform-dirty-summary")
    }

    private var phraseDirtyText: String {
        guard session.workspaceMode == .perform else {
            return "NO PERFORM CHANGES"
        }
        let count = session.phrasePerformOverlay.stagedChangeCount
        return count == 0 ? "NO CHANGES" : "\(count) CHANGED"
    }

    private var phraseLatchTimingControls: some View {
        HStack(spacing: 4) {
            ForEach(TrackPerformLatchMode.allCases) { mode in
                Button {
                    phraseLatchMode = mode
                } label: {
                    Text(mode == .momentary ? "MOM" : "LATCH")
                        .studioText(.microEmphasis)
                        .tracking(0.8)
                        .foregroundStyle(phraseLatchMode == mode ? StudioTheme.background : StudioTheme.mutedText)
                        .frame(width: 58, height: 30)
                        .background(phraseLatchMode == mode ? StudioTheme.amber : StudioTheme.inset, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Button {
                session.performQuantise = session.performQuantise.flipped
            } label: {
                Text(session.performQuantise == .bar ? "Q: BAR" : "Q: OFF")
                    .studioText(.microEmphasis)
                    .tracking(0.8)
                    .foregroundStyle(phraseLatchMode == .latched ? StudioTheme.text : StudioTheme.mutedText)
                    .frame(width: 70, height: 30)
                    .background(phraseLatchMode == .latched ? Color.white.opacity(StudioOpacity.subtleFill) : StudioTheme.inset, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(phraseLatchMode == .latched ? StudioTheme.amber : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
            }
            .buttonStyle(.plain)
            .disabled(phraseLatchMode != .latched)
            .help(phraseLatchMode == .latched ? "Latch changes can land on the next bar" : "Momentary changes are immediate")

            Button {
                phraseLatchLengthBars = nextPhraseLatchLength(after: phraseLatchLengthBars)
            } label: {
                Text(phraseLatchLengthBars.map { "LEN: \($0)B" } ?? "LEN: HOLD")
                    .studioText(.microEmphasis)
                    .tracking(0.8)
                    .foregroundStyle(phraseLatchMode == .latched ? StudioTheme.text : StudioTheme.mutedText)
                    .frame(width: 82, height: 30)
                    .background(phraseLatchMode == .latched ? Color.white.opacity(StudioOpacity.subtleFill) : StudioTheme.inset, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(phraseLatchMode == .latched && phraseLatchLengthBars != nil ? StudioTheme.amber : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
            }
            .buttonStyle(.plain)
            .disabled(phraseLatchMode != .latched)
            .help(phraseLatchMode == .latched ? "Latch can hold until changed or apply for 1, 2, 4, or 8 bars" : "Momentary changes do not use latch length")
        }
        .padding(3)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("phrase-latch-timing")
    }

    private func nextPhraseLatchLength(after current: Int?) -> Int? {
        guard let index = phraseLatchLengthOptions.firstIndex(where: { $0 == current }) else {
            return nil
        }
        return phraseLatchLengthOptions[(index + 1) % phraseLatchLengthOptions.count]
    }

    private var phraseCaptureActions: some View {
        HStack(spacing: 8) {
            Button {
                isPresentingPhraseCapture = true
            } label: {
                Text("Capture")
                    .studioText(.labelBold)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.amber)
            .disabled(!canCapturePhrasePerformOverlay)
            .help(canCapturePhrasePerformOverlay ? "Choose where to save the modified phrase" : "Turn Perform on and make changes before capture")

            Button {
                session.revertPhrasePerformOverlay()
            } label: {
                Text("Discard")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: Capsule())
                    .overlay(Capsule().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
            }
            .buttonStyle(.plain)
            .disabled(!canCapturePhrasePerformOverlay)
            .help("Discard staged phrase perform changes")
        }
    }

    private var canCapturePhrasePerformOverlay: Bool {
        session.workspaceMode == .perform && session.phrasePerformOverlay.isDirty
    }

    private var phraseTabBar: some View {
        HStack(spacing: gridSpacing) {
            ForEach(PhraseWorkspaceTab.allCases) { tab in
                Button {
                    phraseTab = tab
                    isPresentingPerformanceLayerSelection = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: tab.symbolName)
                            .font(.system(size: 12, weight: .bold))
                        Text(tab.label.uppercased())
                            .studioText(.microEmphasis)
                            .tracking(0.8)
                    }
                    .foregroundStyle(phraseTab == tab ? StudioTheme.background : StudioTheme.text)
                    .frame(width: 148, height: 36)
                    .background(phraseTab == tab ? tab.accent : Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                            .stroke(phraseTab == tab ? tab.accent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("phrase-tab-\(tab.rawValue)")
                .help(tab.help)
            }
            Spacer(minLength: 0)
        }
    }

    private var phraseScenesSurface: some View {
        let sceneState = session.resolvedPhraseSceneState(for: session.store.selectedPhrase)
        let sceneA = session.store.masterBus.scene(id: sceneState.sceneAID) ?? session.store.masterBus.activeScene
        let sceneB = session.store.masterBus.scene(id: sceneState.sceneBID)
            ?? session.store.masterBus.scenes.first { $0.id != sceneA.id }
            ?? MasterBusScene.sceneB
        let crossfader = engineController.masterBusPerformanceOverlay.crossfaderOverride ?? sceneState.crossfader

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                phraseSceneSlot(title: "Slot A", scene: sceneA, slot: .a, isDominant: crossfader < 0.5)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                phraseSceneCrossfader(value: crossfader)
                    .frame(width: 180)

                phraseSceneSlot(title: "Slot B", scene: sceneB, slot: .b, isDominant: crossfader > 0.5)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Text("Scene A, crossfader, and Scene B are phrase values. Macro moves remain live scene overrides until the per-scene automation model is added.")
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(2)
        }
        .frame(maxWidth: min(trackGridWidth + phraseColumnWidth + matrixGutterWidth * 2 + actionColumnWidth + gridSpacing * 4, 1120))
        .accessibilityIdentifier("phrase-scenes-surface")
    }

    private var activePhraseSceneSelection: MasterBusABSelection {
        let sceneState = session.resolvedPhraseSceneState(for: session.store.selectedPhrase)
        return MasterBusABSelection(
            sceneAID: sceneState.sceneAID,
            sceneBID: sceneState.sceneBID,
            crossfader: sceneState.crossfader
        )
    }

    private func phraseSceneSlot(
        title: String,
        scene: MasterBusScene,
        slot: ScenePerformSlotPickerRequest.Slot,
        isDominant: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title.uppercased())
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(isDominant ? StudioTheme.amber : StudioTheme.mutedText)

                    Text(scene.name)
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Button {
                    phraseSceneSlotPickerRequest = ScenePerformSlotPickerRequest(slot: slot)
                } label: {
                    HStack(spacing: 5) {
                        Text("Choose")
                            .studioText(.micro)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(StudioTheme.mutedText)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(
                        Color.white.opacity(StudioOpacity.subtleFill),
                        in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                            .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
                }
                .buttonStyle(.plain)
                .help("Choose scene")
            }
            .padding(StudioMetrics.Spacing.comfortable)
            .background(
                Color.white.opacity(StudioOpacity.subtleFill),
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(isDominant ? StudioTheme.amber.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                setPhraseSceneCrossfader(slot == .a ? 0 : 1)
            }

            phraseSceneMacroGrid(scene)
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.amber.opacity(StudioOpacity.hoverFill), lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("phrase-scene-slot-\(slot.rawValue)")
    }

    private func phraseSceneMacroGrid(_ scene: MasterBusScene) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(minimum: 58), spacing: 8), count: 4),
            spacing: 10
        ) {
            ForEach(0..<MasterSceneMacroBinding.slotCount, id: \.self) { slotIndex in
                phraseSceneMacroSlot(slotIndex, scene: scene)
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }

    private func phraseSceneMacroSlot(_ slotIndex: Int, scene: MasterBusScene) -> some View {
        let macro = scene.macroBindings.first { $0.slotIndex == slotIndex }
        return MacroSlotKnob(
            slotIndex: slotIndex,
            descriptor: macro.map {
                MacroSlotKnobDescriptor(displayName: $0.name, valueRange: $0.target.valueRange)
            },
            value: macro.map { phraseSceneMacroValue($0, scene: scene) },
            accent: StudioTheme.amber,
            emptyLabel: "",
            onAssign: {},
            onChange: { value in
                guard let macro else { return }
                engineController.setMasterSceneMacroOverride(sceneID: scene.id, macroID: macro.id, value: value)
            }
        )
    }

    private func phraseSceneMacroValue(_ macro: MasterSceneMacroBinding, scene: MasterBusScene) -> Double {
        let authoredValue = macro.value(in: scene) ?? macro.target.valueRange.lowerBound
        return engineController.masterSceneMacroOverride(sceneID: scene.id, macroID: macro.id) ?? authoredValue
    }

    private func phraseSceneCrossfader(value: Double) -> some View {
        VStack(spacing: 10) {
            Text("\(Int((value * 100).rounded()))%")
                .studioText(.eyebrowBold)
                .monospacedDigit()
                .foregroundStyle(StudioTheme.amber)
                .frame(width: 56, alignment: .center)

            HStack(spacing: 8) {
                Text("A")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.amber)
                    .frame(width: 14, alignment: .leading)

                PhraseSceneCrossfaderTrack(value: value) { nextValue in
                    setPhraseSceneCrossfader(nextValue)
                }
                .frame(height: 42)

                Text("B")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.amber)
                    .frame(width: 14, alignment: .trailing)
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("phrase-scene-crossfader")
    }

    private func phraseSceneSlotPickerSheet(_ request: ScenePerformSlotPickerRequest) -> some View {
        StudioModal(
            title: request.slot.title,
            subtitle: "Choose scene",
            minWidth: 560,
            minHeight: 430,
            onClose: { phraseSceneSlotPickerRequest = nil }
        ) {
            ScrollView {
                LazyVGrid(columns: scenePickerColumns, spacing: 12) {
                    ForEach(session.store.masterBus.scenes) { scene in
                        phraseScenePickerCard(scene, request: request)
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var scenePickerColumns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 104, maximum: 150), spacing: 12),
            count: 4
        )
    }

    private func phraseScenePickerCard(_ scene: MasterBusScene, request: ScenePerformSlotPickerRequest) -> some View {
        let selected = selectedPhraseSceneID(for: request.slot) == scene.id
        return Button {
            setPhraseScene(scene.id, for: request.slot)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? StudioTheme.background : StudioTheme.text)
                        .frame(width: 26, height: 26)
                        .background(selected ? StudioTheme.amber : Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StudioTheme.amber)
                    }
                }

                Text(scene.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(scene.macroBindings.count) macros")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .padding(StudioMetrics.Spacing.comfortable)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(selected ? StudioTheme.amber.opacity(StudioOpacity.ghostStroke) : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func selectedPhraseSceneID(for slot: ScenePerformSlotPickerRequest.Slot) -> UUID {
        let selection = session.store.masterBus.abSelection ?? activePhraseSceneSelection
        switch slot {
        case .a: return selection.sceneAID
        case .b: return selection.sceneBID
        }
    }

    private func setPhraseScene(_ sceneID: UUID, for slot: ScenePerformSlotPickerRequest.Slot) {
        engineController.clearMasterBusPerformanceOverlay()
        let current = session.resolvedPhraseSceneState(for: session.store.selectedPhrase)
        let nextState: PhraseSceneState
        switch slot {
        case .a:
            let sceneBID = current.sceneBID == sceneID ? current.sceneAID : current.sceneBID
            nextState = PhraseSceneState(sceneAID: sceneID, sceneBID: sceneBID, crossfader: current.crossfader)
        case .b:
            let sceneAID = current.sceneAID == sceneID ? current.sceneBID : current.sceneAID
            nextState = PhraseSceneState(sceneAID: sceneAID, sceneBID: sceneID, crossfader: current.crossfader)
        }
        session.setPhraseSceneState(nextState, phraseID: session.store.selectedPhraseID)
        engineController.auditionMasterABSelection(MasterBusABSelection(sceneAID: nextState.sceneAID, sceneBID: nextState.sceneBID, crossfader: nextState.crossfader))
        phraseSceneSlotPickerRequest = nil
    }

    private func setPhraseSceneCrossfader(_ value: Double) {
        let current = session.resolvedPhraseSceneState(for: session.store.selectedPhrase)
        let nextState = PhraseSceneState(sceneAID: current.sceneAID, sceneBID: current.sceneBID, crossfader: value)
        session.setPhraseSceneState(nextState, phraseID: session.store.selectedPhraseID)
        engineController.auditionMasterABSelection(MasterBusABSelection(sceneAID: nextState.sceneAID, sceneBID: nextState.sceneBID, crossfader: nextState.crossfader))
        engineController.setLiveMasterCrossfader(nextState.crossfader)
    }

    private func reconcileSelectedLayer() {
        if matrixSelectableLayers.contains(where: { $0.id == selectedLayerID }) {
            return
        }
        selectedLayerID = matrixSelectableLayers.first?.id ?? session.store.patternLayer?.id ?? layers.first?.id ?? "pattern"
    }

    /// Phrase bar/repeat controls are always visible now; the visual command
    /// keeps working by selecting the requested phrase.
    private func applyVisualControlsOpenIndex() {
        guard let visualControlsOpenIndex,
              phrases.indices.contains(visualControlsOpenIndex)
        else {
            return
        }

        session.setSelectedPhraseID(phrases[visualControlsOpenIndex].id)
    }

    private var layerBar: some View {
        HStack(spacing: gridSpacing) {
            Color.clear
                .frame(width: phraseColumnWidth, height: 44)

            Color.clear
                .frame(width: matrixGutterWidth, height: 44)

            layerSelectorRegion
                .frame(width: trackGridWidth, height: 44)

            Color.clear
                .frame(width: matrixGutterWidth, height: 44)

            Color.clear
                .frame(width: actionColumnWidth, height: 44)
        }
    }

    private var layerSelectorRegion: some View {
        HStack(spacing: gridSpacing) {
            Button {
                isPresentingPerformanceLayerSelection = true
            } label: {
                HStack(spacing: 8) {
                    // Bold-flat pass: solid accent circle with dark glyph.
                    Image(systemName: performanceLayerSelection.mode.symbolName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(StudioTheme.background)
                        .frame(width: 28, height: 28)
                        .background(activeLayerAccent, in: Circle())

                    VStack(alignment: .leading, spacing: 3) {
                        Text("PHRASE LAYER")
                            .studioText(.micro)
                            .tracking(0.8)
                            .foregroundStyle(StudioTheme.mutedText)

                        Text(performanceLayerSelection.activeLabel.uppercased())
                            .studioText(.labelBold)
                            .foregroundStyle(activeLayerAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text(performanceLayerSelection.mode.subtitle)
                            .studioText(.micro)
                            .foregroundStyle(StudioTheme.mutedText)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isPresentingPerformanceLayerSelection ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(activeLayerAccent.opacity(StudioOpacity.subtleStroke), lineWidth: StudioMetrics.borderWidth)
            )
            .accessibilityIdentifier("phrase-layer-selector")
            .help("Choose the Phrase performance layer")

            phraseCellToolButton(.value)
                .frame(width: 104)
            phraseCellToolButton(.automation)
                .frame(width: 132)
        }
        .frame(maxWidth: .infinity)
    }

    private func phraseCellToolButton(_ tool: PhraseCellTool) -> some View {
        Button {
            phraseCellTool = tool
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 13, weight: .bold))
                Text(tool.label.uppercased())
                    .studioText(.microEmphasis)
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(phraseCellTool == tool ? StudioTheme.background : StudioTheme.mutedText)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .background(phraseCellTool == tool ? activeLayerAccent : Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(phraseCellTool == tool ? activeLayerAccent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("phrase-cell-tool-\(tool.rawValue)")
        .help(tool.help)
    }

    private func cycleLayer(by delta: Int) {
        guard !layers.isEmpty else {
            return
        }

        let selectableLayers = matrixSelectableLayers
        guard !selectableLayers.isEmpty else {
            return
        }

        let nextIndex = (selectedLayerIndex + delta + selectableLayers.count) % selectableLayers.count
        selectedLayerID = selectableLayers[nextIndex].id
    }

    private func cycleTrackPage(by delta: Int) {
        trackPage = min(max(trackPage + delta, 0), trackPageCount - 1)
    }

    private func syncTrackPageToSelection() {
        guard let selectedIndex = tracks.firstIndex(where: { $0.id == session.store.selectedTrackID }) else {
            return
        }
        trackPage = min(max(selectedIndex / trackPageSize, 0), trackPageCount - 1)
    }

    private func clampTrackPage() {
        trackPage = min(max(trackPage, 0), trackPageCount - 1)
    }

    private func applyMatrixVisualCommand(_ command: String) {
        if command == "open-layer-selector" {
            isPresentingPerformanceLayerSelection = true
            postRenderedMatrixVisualState(isVisible: true)
            return
        }

        if command == "close-layer-selector" {
            isPresentingPerformanceLayerSelection = false
            postRenderedMatrixVisualState(isVisible: true)
            return
        }

        if command.hasPrefix("select-layer:") {
            let rawMode = String(command.dropFirst("select-layer:".count))
            if let mode = TrackPerformLayerMode(rawValue: rawMode) {
                setPerformanceLayer(mode, variantLabel: nil)
            }
            return
        }

        if command.hasPrefix("select-variant:") {
            let rawSelection = String(command.dropFirst("select-variant:".count))
            let parts = rawSelection.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let mode = TrackPerformLayerMode(rawValue: parts[0])
            else { return }
            setPerformanceLayer(mode, variantLabel: parts[1])
            return
        }

        if command.hasPrefix("page-index:"),
           let rawPageIndex = command.split(separator: ":").last,
           let pageIndex = Int(rawPageIndex) {
            trackPage = min(max(pageIndex, 0), trackPageCount - 1)
            return
        }

        if command.hasPrefix("layer-id:") {
            let layerID = String(command.dropFirst("layer-id:".count))
            if matrixSelectableLayers.contains(where: { $0.id == layerID }) {
                selectedLayerID = layerID
                if let mode = TrackPerformLayerMode.allCases.first(where: { $0.phraseLayerID == layerID }) {
                    performanceLayerSelection.select(mode, variantLabel: nil)
                }
            }
            return
        }

        if command.hasPrefix("layer-index:"),
           let rawIndex = command.split(separator: ":").last,
           let index = Int(rawIndex),
           matrixSelectableLayers.indices.contains(index) {
            selectedLayerID = matrixSelectableLayers[index].id
            if let mode = TrackPerformLayerMode.allCases.first(where: { $0.phraseLayerID == selectedLayerID }) {
                performanceLayerSelection.select(mode, variantLabel: nil)
            }
        }
    }

    private func postRenderedMatrixVisualState(isVisible: Bool) {
        let layout = matrixLayout
        let activeLayer = activeMatrixLayer
        NotificationCenter.default.post(
            name: .phraseMatrixRenderedVisualState,
            object: nil,
            userInfo: [
                "visible": isVisible,
                "pageIndex": isVisible ? layout.pageIndex : 0,
                "pageCount": isVisible ? layout.pageCount : 0,
                "trackCount": isVisible ? tracks.count : 0,
                "previousEnabled": isVisible && layout.arrow(for: .previous).isEnabled,
                "nextEnabled": isVisible && layout.arrow(for: .next).isEnabled,
                "previousOccupancy": isVisible ? layout.arrow(for: .previous).adjacentTrackCount : 0,
                "nextOccupancy": isVisible ? layout.arrow(for: .next).adjacentTrackCount : 0,
                "selectedLayerID": isVisible ? activeLayer?.id ?? "virtual" : "none",
                "selectedLayerName": isVisible ? performanceLayerSelection.activeLabel : "none",
                "selectorWidth": isVisible ? PhraseLayerSelectorPresentation.fixedOuterWidth : 0,
                "trackGridWidth": isVisible ? trackGridWidth : 0,
                "performLayerMode": isVisible ? performanceLayerSelection.mode.rawValue : "none",
                "performLayerSelectorVisible": isVisible && isPresentingPerformanceLayerSelection,
                "performLayerVariant": isVisible ? performanceLayerSelection.variantLabel ?? "none" : "none",
            ]
        )
    }

    private func dismissInvalidEditorTarget() {
        guard let editingCellTarget else {
            return
        }

        let phraseExists = phrases.contains(where: { $0.id == editingCellTarget.phraseID })
        let trackExists = tracks.contains(where: { $0.id == editingCellTarget.trackID })
        let layerExists = layers.contains(where: { $0.id == editingCellTarget.layerID })

        if !(phraseExists && trackExists && layerExists) {
            self.editingCellTarget = nil
        }
    }

    private func handleSingleTap(on phraseID: UUID, trackID: UUID) {
        session.setSelectedPhraseAndTrackID(phraseID: phraseID, trackID: trackID)

        guard phraseCellTool == .value else {
            openCellEditor(phraseID: phraseID, trackID: trackID)
            return
        }

        guard let activeMatrixLayer else {
            return
        }

        switch activeMatrixLayer.valueType {
        case .boolean:
            if NSEvent.modifierFlags.contains(.shift) {
                cascadeBooleanValue(phraseID: phraseID, trackID: trackID)
            } else {
                toggleBooleanCell(phraseID: phraseID, trackID: trackID)
            }
        case .patternIndex:
            cycleIndexedCell(phraseID: phraseID, trackID: trackID)
        case .scalar:
            break
        }
    }

    /// Shift-click: toggle the value, write it into the layer default for the
    /// track, and convert this and every following phrase's cell to inherit it.
    /// A plain click stays a single explicit value on the clicked cell.
    private func cascadeBooleanValue(phraseID: UUID, trackID: UUID) {
        guard let layer = activeMatrixLayer,
              layer.valueType == .boolean,
              let startIndex = phrases.firstIndex(where: { $0.id == phraseID })
        else {
            return
        }

        let phrase = phrases[startIndex]
        let resolvedValue = phrase.resolvedValue(for: layer, trackID: trackID, stepIndex: 0)
        let toggledValue = toggledBooleanValue(resolvedValue, for: layer)

        session.setPhraseLayerDefault(toggledValue, layerID: layer.id, trackID: trackID)
        for followingPhrase in phrases[startIndex...] {
            session.setPhraseCell(
                .inheritDefault,
                layerID: layer.id,
                trackIDs: [trackID],
                phraseID: followingPhrase.id
            )
        }
    }

    /// Vertical drag on a scalar cell edits its value in place, the same way
    /// velocity bars edit on the step sequencer. Dragging an inherited cell
    /// converts it to a single explicit value.
    private func scalarDragGesture(
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition?
    ) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag in
                guard let layer, layer.valueType == .scalar else {
                    return
                }
                let span = layer.maxValue - layer.minValue
                guard span > 0 else {
                    return
                }

                if scalarDragBase?.phraseID != phrase.id || scalarDragBase?.trackID != track.id {
                    let base: Double
                    switch phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0) {
                    case let .scalar(value):
                        base = value
                    case let .index(index):
                        base = Double(index)
                    case let .bool(isOn):
                        base = isOn ? layer.maxValue : layer.minValue
                    }
                    scalarDragBase = (phrase.id, track.id, base)
                }

                guard let dragBase = scalarDragBase else {
                    return
                }
                let next = dragBase.value + Double(-drag.translation.height) / 120 * span
                let clamped = min(max(next, layer.minValue), layer.maxValue)
                session.setPhraseCell(
                    .single(.scalar(clamped)),
                    layerID: layer.id,
                    trackIDs: [track.id],
                    phraseID: phrase.id
                )
            }
            .onEnded { _ in
                scalarDragBase = nil
            }
    }

    private func openCellEditor(phraseID: UUID, trackID: UUID) {
        guard let activeMatrixLayer else { return }
        session.setSelectedPhraseAndTrackID(phraseID: phraseID, trackID: trackID)
        editingCellTarget = PhraseCellEditorTarget(
            phraseID: phraseID,
            trackID: trackID,
            layerID: activeMatrixLayer.id
        )
    }

    private func trackPageArrow(_ direction: PhraseMatrixPageDirection) -> some View {
        let presentation = matrixLayout.arrow(for: direction)
        let systemImage = direction == .previous ? "chevron.left" : "chevron.right"

        return Button {
            cycleTrackPage(by: direction == .previous ? -1 : 1)
        } label: {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .fill(Color.white.opacity(presentation.isEnabled ? StudioOpacity.subtleFill : 0.015))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                            .stroke(StudioTheme.border.opacity(presentation.isEnabled ? StudioOpacity.mediumStroke : StudioOpacity.ghostStroke), lineWidth: StudioMetrics.borderWidth)
                    )

                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(presentation.isEnabled ? StudioTheme.text : StudioTheme.mutedText.opacity(StudioOpacity.ghostStroke))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let occupancyHint = presentation.occupancyHint {
                    Text(occupancyHint)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .frame(width: 15, height: 15)
                        .background(activeLayerAccent, in: Circle())
                        .offset(x: 3, y: -3)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!presentation.isEnabled)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier(direction == .previous ? "phrase-matrix-page-previous" : "phrase-matrix-page-next")
    }

    private var matrix: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: gridSpacing) {
                let activeLayer = activeMatrixLayer
                let accent = activeLayerAccent
                HStack(spacing: gridSpacing) {
                    Color.clear
                        .frame(width: phraseColumnWidth, height: 52)

                    trackPageArrow(.previous)
                        .frame(width: matrixGutterWidth, height: 52)

                    ForEach(Array(visibleTrackSlots.enumerated()), id: \.offset) { _, track in
                        Group {
                            if let track {
                                Button {
                                    session.setSelectedTrackID(track.id)
                                } label: {
                                    PhraseMatrixTrackHeaderCell(
                                        track: track,
                                        isSelected: selectedTrack.id == track.id,
                                        accent: track.groupID == nil ? accent : StudioTheme.success
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                PhraseMatrixEmptyTrackHeaderCell()
                            }
                        }
                        .frame(width: trackColumnWidth)
                    }

                    trackPageArrow(.next)
                        .frame(width: matrixGutterWidth, height: 52)

                    Color.clear
                        .frame(width: actionColumnWidth, height: 52)
                }

                let selectedPhraseID = session.store.selectedPhraseID
                let selectedTrackID = session.store.selectedTrackID
                ForEach(Array(phrases.enumerated()), id: \.element.id) { index, phrase in
                    let displayedPhrase = session.phraseWithPerformOverlay(phrase)
                    VStack(alignment: .leading, spacing: 6) {
                        // A fixed row height lets every cell stretch to the
                        // same bounds, keeping the strip aligned (ux-canon 9).
                        HStack(alignment: .top, spacing: gridSpacing) {
                            PhraseMatrixPhraseCell(
                                phrase: phrase,
                                isSelected: selectedPhraseID == phrase.id,
                                isPlaying: PhraseButtonControlPresentation.isPlayingBadgeVisible(
                                    phraseID: phrase.id,
                                    engineIsRunning: engineController.isRunning,
                                    currentPhraseID: engineController.currentPhraseID
                                ),
                                isQueued: engineController.queuedPhraseID == phrase.id,
                                onSelect: {
                                    session.setSelectedPhraseID(phrase.id)
                                },
                                onChangeBarCount: { nextBarCount in
                                    session.setPhraseBarCount(nextBarCount, phraseID: phrase.id)
                                },
                                onChangeRepeatCount: { nextRepeatCount in
                                    session.setPhraseRepeatCount(nextRepeatCount, phraseID: phrase.id)
                                }
                            )
                            .frame(width: phraseColumnWidth)

                            PhraseMatrixGutterCell()
                                .frame(width: matrixGutterWidth)

                            ForEach(Array(visibleTrackSlots.enumerated()), id: \.offset) { _, track in
                                Group {
                                    if let track {
                                        Group {
                                            if let activeLayer {
                                                PhraseGridCell(
                                                    layer: activeLayer,
                                                    cell: displayedPhrase.cell(for: activeLayer.id, trackID: track.id),
                                                    phrase: displayedPhrase,
                                                    track: track,
                                                    isSelected: phrase.id == selectedPhraseID && track.id == selectedTrackID,
                                                    accent: accent
                                                )
                                            } else {
                                                PhrasePerformancePlaceholderCell(
                                                    selection: performanceLayerSelection,
                                                    phrase: displayedPhrase,
                                                    track: track,
                                                    isSelected: phrase.id == selectedPhraseID && track.id == selectedTrackID,
                                                    accent: accent
                                                )
                                            }
                                        }
                                        .contentShape(Rectangle())
                                        .gesture(
                                            TapGesture()
                                                .onEnded {
                                                    handleSingleTap(on: phrase.id, trackID: track.id)
                                                }
                                        )
                                        .simultaneousGesture(
                                            scalarDragGesture(phrase: displayedPhrase, track: track, layer: activeLayer)
                                        )
                                    } else {
                                        PhraseGridEmptyCell()
                                    }
                                }
                                .frame(width: trackColumnWidth)
                            }

                            PhraseMatrixGutterCell()
                                .frame(width: matrixGutterWidth)

                            PhraseRowActions(
                                canRemove: phrases.count > 1,
                                onInsertBelow: {
                                    session.insertPhrase(below: phrase.id)
                                },
                                onDuplicate: {
                                    session.duplicatePhrase(id: phrase.id)
                                },
                                onRemove: {
                                    session.removePhrase(id: phrase.id)
                                }
                            )
                            .frame(width: actionColumnWidth)
                        }
                        .frame(height: PhraseMatrixLayoutPresentation.matrixRowHeight)

                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        .frame(minHeight: 280)
    }

    private func toggleBooleanCell(phraseID: UUID, trackID: UUID) {
        guard let selectedLayer = activeMatrixLayer, selectedLayer.valueType == .boolean else {
            assertionFailure("toggleBooleanCell called without an active boolean phrase layer")
            return
        }

        guard let phrase = phrases.first(where: { $0.id == phraseID }) else {
            return
        }

        let displayedPhrase = session.phraseWithPerformOverlay(phrase)
        let currentCell = displayedPhrase.cell(for: selectedLayer.id, trackID: trackID)
        let resolvedValue = displayedPhrase.resolvedValue(for: selectedLayer, trackID: trackID, stepIndex: 0)
        let toggledValue = toggledBooleanValue(resolvedValue, for: selectedLayer)

        if PhrasePerformTimingPolicy.usesQuantisedLayerArming(
            layerID: selectedLayer.id,
            latchMode: phraseLatchMode,
            sessionArmingActive: session.isQuantisedPerformToggleArmingActive
        ) {
            if selectedLayer.id == TrackPerformLayerMode.mute.phraseLayerID {
                session.toggleQuantisedMute(
                    trackIDs: [trackID],
                    basisPhrase: displayedPhrase,
                    layer: selectedLayer,
                    stepIndex: 0,
                    lengthBars: phraseLatchLengthBars
                )
            } else if selectedLayer.id == TrackPerformLayerMode.fill.phraseLayerID {
                session.toggleQuantisedFillFlag(
                    trackIDs: [trackID],
                    basisPhrase: displayedPhrase,
                    layer: selectedLayer,
                    stepIndex: 0,
                    lengthBars: phraseLatchLengthBars
                )
            }
            return
        }

        let nextCell: PhraseCell
        switch currentCell {
        case .inheritDefault, .curve:
            nextCell = .single(toggledValue)
        case .single:
            nextCell = .single(toggledValue)
        case let .bars(values):
            nextCell = .bars(Array(repeating: toggledValue, count: values.count))
        case let .steps(values):
            nextCell = .steps(Array(repeating: toggledValue, count: values.count))
        }

        session.setPhraseCell(
            nextCell,
            layerID: selectedLayer.id,
            trackIDs: [trackID],
            phraseID: phraseID
        )
    }

    private func cycleIndexedCell(phraseID: UUID, trackID: UUID) {
        guard let selectedLayer = activeMatrixLayer, selectedLayer.valueType == .patternIndex else {
            assertionFailure("cycleIndexedCell called without an active indexed phrase layer")
            return
        }

        guard let phrase = phrases.first(where: { $0.id == phraseID }) else {
            return
        }

        let displayedPhrase = session.phraseWithPerformOverlay(phrase)
        let currentCell = displayedPhrase.cell(for: selectedLayer.id, trackID: trackID)
        let resolvedValue = displayedPhrase.resolvedValue(for: selectedLayer, trackID: trackID, stepIndex: 0)
        let currentIndex: Int
        if case let .index(index) = resolvedValue.normalized(for: selectedLayer) {
            currentIndex = index
        } else {
            currentIndex = 0
        }
        let nextValue = PhraseCellValue.index((currentIndex + 1) % TrackPatternBank.slotCount)

        if PhrasePerformTimingPolicy.usesQuantisedLayerArming(
            layerID: selectedLayer.id,
            latchMode: phraseLatchMode,
            sessionArmingActive: session.isQuantisedPerformToggleArmingActive
        ) {
            session.toggleQuantisedPatternIndex(
                trackIDs: [trackID],
                basisPhrase: displayedPhrase,
                layer: selectedLayer,
                stepIndex: 0,
                lengthBars: phraseLatchLengthBars
            )
            return
        }

        let nextCell: PhraseCell
        switch currentCell {
        case .inheritDefault, .curve:
            nextCell = .single(nextValue)
        case .single:
            nextCell = .single(nextValue)
        case let .bars(values):
            nextCell = .bars(Array(repeating: nextValue, count: values.count))
        case let .steps(values):
            nextCell = .steps(Array(repeating: nextValue, count: values.count))
        }

        session.setPhraseCell(
            nextCell,
            layerID: selectedLayer.id,
            trackIDs: [trackID],
            phraseID: phraseID
        )
    }

    private var globalApplySurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            globalApplyScopeBar

            if isPresentingGlobalApplyTrackSelector {
                globalApplyTrackSelector
            }

            LazyVGrid(columns: globalApplyColumns, alignment: .leading, spacing: 10) {
                ForEach(globalApplyOptions) { option in
                    globalApplyActionCell(option)
                }
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(StudioTheme.background, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(StudioTheme.amber, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("phrase-global-apply-surface")
    }

    private var globalApplyScopeBar: some View {
        HStack(spacing: gridSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GLOBAL APPLY")
                    .studioText(.microEmphasis)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.amber)
                Text("\(globalApplyScopeTitle) • \(selectedPhraseForEditing.name)")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )

            Button {
                isPresentingGlobalApplyTrackSelector.toggle()
            } label: {
                Text(isPresentingGlobalApplyTrackSelector ? "Hide Tracks" : "Track Selector")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 132, height: 44)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                            .stroke(isPresentingGlobalApplyTrackSelector ? StudioTheme.amber : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
            }
            .buttonStyle(.plain)

            Button {
                selectAllGlobalApplyTracks()
            } label: {
                Text("All Tracks")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .frame(width: 92, height: 44)
                    .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous).stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
            }
            .buttonStyle(.plain)
        }
    }

    private var globalApplyTrackSelector: some View {
        LazyVGrid(columns: globalApplyColumns, alignment: .leading, spacing: 10) {
            ForEach(tracks, id: \.id) { track in
                let isSelected = globalApplyScope.contains(track.id) || globalApplyScope.isEmpty
                Button {
                    if globalApplyScope.isEmpty {
                        globalApplyScope.add(track.id)
                    } else {
                        globalApplyScope.toggle(track.id)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(isSelected ? StudioTheme.amber : StudioTheme.mutedText)
                            Spacer(minLength: 0)
                        }
                        Text(track.name)
                            .studioText(.labelBold)
                            .foregroundStyle(StudioTheme.text)
                            .lineLimit(1)
                        Text(track.trackType.shortLabel.uppercased())
                            .studioText(.micro)
                            .tracking(0.8)
                            .foregroundStyle(StudioTheme.mutedText)
                    }
                    .padding(StudioMetrics.Spacing.compact)
                    .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
                    .background(isSelected ? Color.white.opacity(StudioOpacity.subtleFill) : Color.clear, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                            .stroke(isSelected ? StudioTheme.amber : StudioTheme.border, lineWidth: isSelected ? 2 : StudioMetrics.borderWidth)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("phrase-global-apply-track-selector")
    }

    private func globalApplyActionCell(_ option: PerformanceLayerOption) -> some View {
        let accent = option.mode.selectorAccent
        return Button {
            applyGlobalOption(option)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: option.mode.symbolName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(accent)
                    Spacer(minLength: 0)
                    Text(globalApplyPreview(option))
                        .studioText(.microEmphasis)
                        .tracking(0.7)
                        .foregroundStyle(StudioTheme.text)
                }

                Spacer(minLength: 0)

                Text(option.title.uppercased())
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)

                Text("Apply to \(globalApplyScopeCount) track\(globalApplyScopeCount == 1 ? "" : "s")")
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
            .padding(StudioMetrics.Spacing.compact)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .topLeading)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(accent, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var phraseLocalPerformanceLayerOptions: [PerformanceLayerOption] {
        PerformanceLayerOption.all.filter { option in
            guard let layerID = option.mode.phraseLayerID else { return false }
            return matrixSelectableLayers.contains { $0.id == layerID }
        }
    }

    private var globalApplyOptions: [PerformanceLayerOption] {
        phraseLocalPerformanceLayerOptions
    }

    private var globalApplyColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 84, maximum: 190), spacing: 10), count: 8)
    }

    private var globalApplyScopeTrackIDs: [UUID] {
        let orderedTrackIDs = tracks.map(\.id)
        if globalApplyScope.isEmpty {
            return orderedTrackIDs
        }
        return orderedTrackIDs.filter { globalApplyScope.contains($0) }
    }

    private var globalApplyScopeCount: Int {
        globalApplyScopeTrackIDs.count
    }

    private var globalApplyScopeTitle: String {
        if globalApplyScope.isEmpty {
            return "All \(tracks.count) tracks"
        }
        return "\(globalApplyScopeCount) selected"
    }

    private func selectAllGlobalApplyTracks() {
        globalApplyScope.clear()
    }

    private func globalApplyPreview(_ option: PerformanceLayerOption) -> String {
        guard let layerID = option.mode.phraseLayerID,
              let layer = layers.first(where: { $0.id == layerID }),
              let seedTrackID = globalApplyScopeTrackIDs.first
        else {
            return "Ready"
        }

        let value = selectedPhraseForEditing.resolvedValue(for: layer, trackID: seedTrackID, stepIndex: 0)
        return valueLabel(cycledValue(value, for: layer), layer: layer)
    }

    private func applyGlobalOption(_ option: PerformanceLayerOption) {
        guard let layerID = option.mode.phraseLayerID,
              let layer = layers.first(where: { $0.id == layerID }),
              let seedTrackID = globalApplyScopeTrackIDs.first
        else {
            return
        }

        performanceLayerSelection.select(option.mode, variantLabel: option.variantLabel)
        selectedLayerID = layer.id

        let phrase = selectedPhraseForEditing
        let nextValue = cycledValue(
            phrase.resolvedValue(for: layer, trackID: seedTrackID, stepIndex: 0),
            for: layer
        )
        if PhrasePerformTimingPolicy.usesQuantisedLayerArming(
            layerID: layer.id,
            latchMode: phraseLatchMode,
            sessionArmingActive: session.isQuantisedPerformToggleArmingActive
        ) {
            if layer.id == TrackPerformLayerMode.mute.phraseLayerID {
                session.toggleQuantisedMute(
                    trackIDs: globalApplyScopeTrackIDs,
                    basisPhrase: phrase,
                    layer: layer,
                    stepIndex: 0,
                    lengthBars: phraseLatchLengthBars
                )
            } else if layer.id == TrackPerformLayerMode.fill.phraseLayerID {
                session.toggleQuantisedFillFlag(
                    trackIDs: globalApplyScopeTrackIDs,
                    basisPhrase: phrase,
                    layer: layer,
                    stepIndex: 0,
                    lengthBars: phraseLatchLengthBars
                )
            } else if layer.id == TrackPerformLayerMode.pattern.phraseLayerID {
                session.toggleQuantisedPatternIndex(
                    trackIDs: globalApplyScopeTrackIDs,
                    basisPhrase: phrase,
                    layer: layer,
                    stepIndex: 0,
                    lengthBars: phraseLatchLengthBars
                )
            }
            return
        }

        session.setPhraseCell(
            .single(nextValue),
            layerID: layer.id,
            trackIDs: globalApplyScopeTrackIDs,
            phraseID: phrase.id
        )
    }

    private var performanceLayerSelectionSurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Text("CHOOSE PHRASE LAYER")
                    .studioText(.microEmphasis)
                    .tracking(0.8)
                    .foregroundStyle(StudioTheme.amber)

                Spacer(minLength: 8)

                StudioCircleIconButton(
                    systemName: "xmark",
                    help: "Return to phrase rows"
                ) {
                    isPresentingPerformanceLayerSelection = false
                    postRenderedMatrixVisualState(isVisible: true)
                }
            }

            LazyVGrid(columns: performanceLayerSelectionColumns, alignment: .leading, spacing: 10) {
                ForEach(phraseLocalPerformanceLayerOptions) { option in
                    PerformanceLayerOptionCell(
                        option: option,
                        isSelected: performanceLayerSelection.mode == option.mode
                            && performanceLayerSelection.variantLabel == option.variantLabel
                    ) {
                        choosePerformanceLayer(option)
                    }
                }
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        // Bold-flat pass: the selector sits on the ground behind a solid
        // amber outline — no tinted wash.
        .background(StudioTheme.background, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.section, style: .continuous)
                .stroke(StudioTheme.amber, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("phrase-performance-layer-selection-surface")
    }

    private var performanceLayerSelectionColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 84, maximum: 190), spacing: 10), count: 8)
    }

    private func choosePerformanceLayer(_ option: PerformanceLayerOption) {
        let isAlreadySelected = performanceLayerSelection.mode == option.mode
            && performanceLayerSelection.variantLabel == option.variantLabel
        if isAlreadySelected, option.variantLabel != nil {
            // Variant cells toggle: off returns to normal pattern playback.
            performanceLayerSelection.select(.pattern, variantLabel: nil)
        } else {
            performanceLayerSelection.select(option.mode, variantLabel: option.variantLabel)
        }
        if let layerID = performanceLayerSelection.mode.phraseLayerID,
           matrixSelectableLayers.contains(where: { $0.id == layerID }) {
            selectedLayerID = layerID
        }
        isPresentingPerformanceLayerSelection = false
        postRenderedMatrixVisualState(isVisible: true)
    }

    /// Idempotent variant used by visual automation commands: always selects,
    /// never toggles off.
    private func setPerformanceLayer(_ mode: TrackPerformLayerMode, variantLabel: String?) {
        performanceLayerSelection.select(mode, variantLabel: variantLabel)
        if let layerID = performanceLayerSelection.mode.phraseLayerID,
           matrixSelectableLayers.contains(where: { $0.id == layerID }) {
            selectedLayerID = layerID
        }
        isPresentingPerformanceLayerSelection = false
        postRenderedMatrixVisualState(isVisible: true)
    }
}

private enum PhraseCellTool: String, Equatable {
    case value
    case automation

    var label: String {
        switch self {
        case .value:
            return "Value"
        case .automation:
            return "Automation"
        }
    }

    var symbolName: String {
        switch self {
        case .value:
            return "cursorarrow.click"
        case .automation:
            return "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    var help: String {
        switch self {
        case .value:
            return "Cell clicks change the selected layer value"
        case .automation:
            return "Cell clicks open automation editing for the selected layer"
        }
    }
}

private enum PhraseWorkspaceTab: String, CaseIterable, Identifiable {
    case layers
    case scenes
    case globalApply

    var id: String { rawValue }

    var label: String {
        switch self {
        case .layers:
            return "Layers"
        case .scenes:
            return "Scenes"
        case .globalApply:
            return "Global Apply"
        }
    }

    var symbolName: String {
        switch self {
        case .layers:
            return "square.grid.3x3"
        case .scenes:
            return "square.2.layers.3d"
        case .globalApply:
            return "scope"
        }
    }

    var accent: Color {
        switch self {
        case .layers:
            return StudioTheme.violet
        case .scenes:
            return StudioTheme.amber
        case .globalApply:
            return StudioTheme.cyan
        }
    }

    var help: String {
        switch self {
        case .layers:
            return "Edit phrase layer values by track"
        case .scenes:
            return "Edit phrase scene values"
        case .globalApply:
            return "Apply one value to the current track scope"
        }
    }
}

private struct PhraseRowActions: View {
    let canRemove: Bool
    let onInsertBelow: () -> Void
    let onDuplicate: () -> Void
    let onRemove: () -> Void

    // The three row actions sit in one bordered container so they read as a
    // single control cluster rather than loose buttons (ux-canon rule 9).
    var body: some View {
        HStack(spacing: 6) {
            actionButton(systemImage: "plus", action: onInsertBelow)
            actionButton(systemImage: "plus.square.on.square", action: onDuplicate)
            actionButton(systemImage: "trash", action: onRemove, isDisabled: !canRemove)
        }
        .padding(6)
        .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .frame(maxHeight: .infinity, alignment: .center)
    }

    private func actionButton(systemImage: String, action: @escaping () -> Void, isDisabled: Bool = false) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(isDisabled ? StudioTheme.mutedText.opacity(StudioOpacity.inheritedContent) : StudioTheme.text)
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct PhraseMatrixGutterCell: View {
    var body: some View {
        Color.clear
            .accessibilityHidden(true)
    }
}

private struct PhraseMatrixTrackHeaderCell: View {
    let track: StepSequenceTrack
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.name)
                .studioText(.subtitle)
                .foregroundStyle(StudioTheme.text)
            Text(track.trackType.label.uppercased())
                .studioText(.microEmphasis)
                .tracking(0.8)
                .foregroundStyle(StudioTheme.mutedText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        // Colour identifies, it never floods (ux-canon rule 12): outline-only
        // header cell — drawn border-grey line when idle, solid accent line
        // when selected, body on the neutral step.
        .background((isSelected ? Color.white.opacity(StudioOpacity.subtleFill) : Color.clear), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(isSelected ? accent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
    }
}

private struct PhraseMatrixEmptyTrackHeaderCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
            .fill(StudioTheme.inset)
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(StudioOpacity.ghostStroke), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [5, 5]))
            )
    }
}

private struct PhraseSceneCrossfaderTrack: View {
    let value: Double
    let onChange: (Double) -> Void

    private var clampedValue: Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let thumbX = width * clampedValue

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(StudioTheme.border.opacity(0.8))
                    .frame(height: 10)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)

                Capsule()
                    .fill(StudioTheme.amber)
                    .frame(width: thumbX, height: 10)
                    .frame(maxHeight: .infinity, alignment: .center)

                Circle()
                    .fill(StudioTheme.amber)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(StudioOpacity.ghostStroke), lineWidth: 2)
                    )
                    .offset(x: min(max(thumbX - 14, 0), width - 28))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let x = min(max(drag.location.x, 0), width)
                        onChange(Double(x / width))
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Phrase scene crossfader")
        .accessibilityValue("\(Int((clampedValue * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onChange(min(clampedValue + 0.05, 1))
            case .decrement:
                onChange(max(clampedValue - 0.05, 0))
            @unknown default:
                break
            }
        }
    }
}

private struct PhraseMatrixPhraseCell: View {
    let phrase: PhraseModel
    let isSelected: Bool
    let isPlaying: Bool
    let isQueued: Bool
    let onSelect: () -> Void
    let onChangeBarCount: (Int) -> Void
    let onChangeRepeatCount: (Int) -> Void

    private var presentation: PhraseButtonControlPresentation {
        PhraseButtonControlPresentation(
            phrase: phrase,
            isSelected: isSelected,
            isPlaying: isPlaying,
            isQueued: isQueued
        )
    }

    // Bars and repeat edit in place, always visible: no collapsed summary
    // duplicating the stepper values, no SEL badge (selection is the cell
    // chrome), no loop toggle (transport Song/Free owns that decision).
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onSelect) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(phrase.name)
                        .studioText(.subtitle)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(phrase.name)
                        .layoutPriority(1)

                    Spacer(minLength: 0)

                    if isPlaying {
                        phraseBadge("Play", accent: StudioTheme.success)
                    }
                    if isQueued {
                        phraseBadge("Queue", accent: StudioTheme.amber)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(presentation.accessibilityLabel)
            .accessibilityHint("Select phrase")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("phrase-button-\(phrase.id.uuidString)")

            PhrasePolicyStepperControl(
                title: "Bars",
                valueLabel: presentation.barCountSummary,
                decrementDisabled: phrase.lengthBars <= PhraseModel.lengthBarsRange.lowerBound,
                incrementDisabled: phrase.lengthBars >= PhraseModel.lengthBarsRange.upperBound,
                onDecrement: {
                    onChangeBarCount(PhraseModel.clampedLengthBars(phrase.lengthBars - 1))
                },
                onIncrement: {
                    onChangeBarCount(PhraseModel.clampedLengthBars(phrase.lengthBars + 1))
                }
            )

            PhrasePolicyStepperControl(
                title: "Repeat",
                valueLabel: presentation.repeatValueLabel,
                decrementDisabled: phrase.repeatCount <= PhraseModel.repeatCountRange.lowerBound,
                incrementDisabled: phrase.repeatCount >= PhraseModel.repeatCountRange.upperBound,
                onDecrement: {
                    onChangeRepeatCount(PhraseModel.clampedRepeatCount(phrase.repeatCount - 1))
                },
                onIncrement: {
                    onChangeRepeatCount(PhraseModel.clampedRepeatCount(phrase.repeatCount + 1))
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.compact)
        .background(rowFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(rowStroke, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("phrase-button-controls-\(phrase.id.uuidString)")
    }

    /// Colour identifies, it never floods (ux-canon rule 12): row state lives
    /// in a solid drawn outline (success = playing, amber = queued/looping,
    /// violet = selected, border grey otherwise) plus the solid badges; the
    /// fill stays on the neutral step.
    private var rowFill: Color {
        if phrase.loopEnabled || isSelected {
            return Color.white.opacity(StudioOpacity.subtleFill)
        }
        return Color.clear
    }

    private var rowStroke: Color {
        if isPlaying {
            return StudioTheme.success
        }
        if isQueued || phrase.loopEnabled {
            return StudioTheme.amber
        }
        return isSelected ? StudioTheme.violet : StudioTheme.border
    }

    // Bold-flat pass: badges are solid accent blocks with dark text.
    private func phraseBadge(_ label: String, accent: Color) -> some View {
        Text(label.uppercased())
            .studioText(.microEmphasis)
            .lineLimit(1)
            .foregroundStyle(StudioTheme.background)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(accent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
    }
}

private struct PhrasePolicyStepperControl: View {
    let title: String
    let valueLabel: String
    var footnote: String? = nil
    let decrementDisabled: Bool
    let incrementDisabled: Bool
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    // No label above the stepper: the value text carries the meaning and the
    // title lives in the tooltip and accessibility label (ux-canon rule 3).
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                stepButton(systemName: "minus", action: onDecrement, isDisabled: decrementDisabled)

                Text(valueLabel)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(Color.white.opacity(StudioOpacity.subtleFill))

                stepButton(systemName: "plus", action: onIncrement, isDisabled: incrementDisabled)
            }
            .clipShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )

            if let footnote {
                Text(footnote)
                    .studioText(.micro)
                    .foregroundStyle(StudioTheme.mutedText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(title)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title) \(valueLabel)")
    }

    private func stepButton(systemName: String, action: @escaping () -> Void, isDisabled: Bool) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isDisabled ? StudioTheme.mutedText.opacity(StudioOpacity.ghostStroke) : StudioTheme.text)
                .frame(width: 28, height: 30)
                .background(Color.white.opacity(isDisabled ? 0.015 : StudioOpacity.subtleFill))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct PhraseGridCell: View {
    let layer: PhraseLayerDefinition
    let cell: PhraseCell
    let phrase: PhraseModel
    let track: StepSequenceTrack
    let isSelected: Bool
    let accent: Color

    // Inherited cells are a muted variant of explicit ones — no
    // "SINGLE"/"INHERIT" chip repeated in every cell (ux-canon rules 1/3).
    private var isInherited: Bool {
        cell.editMode == .inheritDefault
    }

    var body: some View {
        PhraseCellPreview(
            layer: layer,
            cell: cell,
            resolvedValue: phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0),
            accent: accent,
            summary: valueLabel(phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0), layer: layer),
            metrics: .matrix
        )
        .opacity(isInherited ? StudioOpacity.inheritedContent : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(StudioMetrics.Spacing.compact)
        // Bold-flat pass: no container fill — the cell preview is the block,
        // sitting directly on the ground (one less nesting level). The
        // container only draws a line when selected or inherited.
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(
                    isSelected ? accent : (isInherited ? StudioTheme.border : Color.clear),
                    style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: isInherited && !isSelected ? StudioAddCard.dashPattern : [])
                )
        )
        .help(isInherited ? "Follows the layer default. Click to set its own value; shift-click to push a value into this and the following phrases." : "")
    }
}

private struct PhrasePerformancePlaceholderCell: View {
    let selection: PerformanceLayerSelectionState
    let phrase: PhraseModel
    let track: StepSequenceTrack
    let isSelected: Bool
    let accent: Color

    private var detail: String {
        switch selection.mode {
        case .noteRepeat:
            return "Repeat target"
        case .stepOrder:
            return "Step map"
        case .pan:
            return "Pan target"
        case .mute, .pattern, .fill, .volume:
            return "\(phrase.name) / \(track.name)"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The active layer is named once in the matrix header; cells only
            // carry the layer icon and their own target identity.
            Image(systemName: selection.mode.symbolName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)

            Text(detail)
                .studioText(.labelBold)
                .foregroundStyle(StudioTheme.text)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(StudioMetrics.Spacing.compact)
        // Colour identifies, it never floods (ux-canon rule 12): outline-only
        // cell — border-grey line when idle, solid accent line when selected,
        // body on the neutral step.
        .background((isSelected ? Color.white.opacity(StudioOpacity.subtleFill) : Color.clear), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(isSelected ? accent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityLabel("\(phrase.name), \(track.name), \(selection.activeLabel), selection only")
    }
}

private struct PhraseGridEmptyCell: View {
    var body: some View {
        RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
            .fill(StudioTheme.inset)
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(StudioOpacity.ghostStroke), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [5, 5]))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
