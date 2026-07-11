import SwiftUI

private enum PhraseTrackScopeChoice: Hashable {
    case all
    case currentSelection
    case group(Int)
}

struct PhraseDocumentEditClipboard: Equatable {
    let phrase: PhraseModel
}

struct PhraseCellDocumentEditClipboard: Equatable {
    let layerID: String
    let cell: PhraseCell

    func isCompatible(with layerID: String) -> Bool {
        self.layerID == layerID
    }
}

struct PhraseCellDocumentSelection: Equatable {
    private(set) var phraseID: UUID?
    private(set) var layerID: String?
    private(set) var trackIDs: Set<UUID> = []

    var isEmpty: Bool { trackIDs.isEmpty }
    var count: Int { trackIDs.count }
    var first: UUID? { trackIDs.first }

    mutating func select(phraseID: UUID, layerID: String, trackID: UUID, additive: Bool) {
        if self.phraseID != phraseID || self.layerID != layerID || !additive {
            trackIDs.removeAll()
        }
        self.phraseID = phraseID
        self.layerID = layerID
        trackIDs.insert(trackID)
    }

    mutating func applySelectionGesture(
        _ gesture: StudioSelectionGesture,
        phraseID: UUID,
        layerID: String,
        trackID: UUID
    ) {
        let matchesScope = self.phraseID == phraseID && self.layerID == layerID
        let scopedSelection = matchesScope ? trackIDs : []
        trackIDs = gesture.selection(targeting: trackID, in: scopedSelection)

        if trackIDs.isEmpty {
            clear()
        } else {
            self.phraseID = phraseID
            self.layerID = layerID
        }
    }

    func contains(_ trackID: UUID) -> Bool {
        trackIDs.contains(trackID)
    }

    func matchingTrackIDs(phraseID: UUID, layerID: String, liveTrackIDs: [UUID]) -> [UUID] {
        guard self.phraseID == phraseID, self.layerID == layerID else { return [] }
        return liveTrackIDs.filter { trackIDs.contains($0) }
    }

    mutating func reconcile(phraseID: UUID, layerID: String?, liveTrackIDs: [UUID]) {
        guard self.phraseID == phraseID, self.layerID == layerID, layerID != nil else {
            clear()
            return
        }
        trackIDs.formIntersection(liveTrackIDs)
        if trackIDs.isEmpty {
            clear()
        }
    }

    mutating func clear() {
        phraseID = nil
        layerID = nil
        trackIDs.removeAll()
    }
}

private struct PhraseDocumentEditRevision: Equatable {
    let selectedPhraseID: UUID
    let phraseIDs: [UUID]
    let activeLayerID: String?
    let cellSelection: PhraseCellDocumentSelection
    let usesCellTarget: Bool
}

private struct PhraseCellSelectionContext: Equatable {
    let phraseID: UUID
    let layerID: String?
    let liveTrackIDs: [UUID]
    let isCellSurfaceVisible: Bool
}

@MainActor
private func phraseDocumentEditTarget(
    session: SequencerDocumentSession
) -> DocumentEditCommandController.Target {
    .init(
        canCopy: {
            session.store.phrases.contains { $0.id == session.store.selectedPhraseID }
        },
        canClear: { false },
        isPasteCompatible: { payload in
            payload.domain == .phrases
                && payload.value(as: PhraseDocumentEditClipboard.self) != nil
                && session.store.phrases.contains { $0.id == session.store.selectedPhraseID }
        },
        copy: {
            guard let phrase = session.store.phrases.first(where: { $0.id == session.store.selectedPhraseID }) else {
                return nil
            }
            return .init(
                domain: .phrases,
                snapshot: PhraseDocumentEditClipboard(phrase: phrase)
            )
        },
        paste: { payload in
            guard let clipboard = payload.value(as: PhraseDocumentEditClipboard.self) else { return }
            _ = session.insertPhraseCopy(
                clipboard.phrase,
                below: session.store.selectedPhraseID
            )
        },
        clearSelection: {}
    )
}

enum PhraseSceneHardSwitch {
    static func crossfaderValue(for slot: ScenePerformSlotPickerRequest.Slot) -> Double {
        slot == .a ? 0 : 1
    }
}

struct PhraseWorkspaceView: View {
    @Binding var document: SeqAIDocument
    @Binding private var visualControlsOpenIndex: Int?
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    @State private var selectedLayerID = "pattern"
    @State private var editingCellTarget: PhraseCellEditorTarget?
    @State private var trackPage = 0
    @State private var phraseTab: PhraseWorkspaceTab = .layers
    @State private var phraseLayerEditMode: PhraseLayerEditMode = .byTrack
    @State private var phraseSceneViewMode: PhraseSceneViewMode = .macros
    @State private var performanceLayerSelection = PerformanceLayerSelectionState()
    @State private var isPresentingPerformanceLayerSelection = false
    @State private var phraseCellTool: PhraseCellTool = .value
    @State private var isPresentingGlobalApplyTrackSelector = false
    @State private var trackScopeChoice: PhraseTrackScopeChoice = .all
    @State private var phraseSceneSlotPickerRequest: ScenePerformSlotPickerRequest?
    @State private var isPresentingPhraseCapture = false
    @State private var finiteChoiceTarget: PhraseFiniteChoiceTarget?
    @State private var phraseLatchMode: TrackPerformLatchMode = .momentary
    @State private var phraseLatchLengthBars: Int?
    @State private var scalarDragBase: (phraseID: UUID, trackID: UUID, value: Double)?
    @State private var phraseLayerSelection = PhraseCellDocumentSelection()

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

    /// Forward-only inherited defaults for one phrase, so matrix cells display
    /// the value they will actually play (the nearest preceding explicit value
    /// in song order), matching the engine compile path.
    private func inheritedDefaults(for phraseID: UUID) -> PhraseInheritedDefaults.Resolved {
        PhraseInheritedDefaults
            .build(phrases: phrases, layers: layers)
            .resolved(for: phraseID)
    }
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
        activeMatrixLayer.map { layerAccent($0.id) } ?? performanceLayerSelection.mode.phraseAccent
    }

    private var trackPageCount: Int {
        matrixLayout.pageCount
    }

    private var matrixLayout: PhraseMatrixLayoutPresentation {
        PhraseMatrixLayoutPresentation(trackCount: scopedLayerTracks.count, pageIndex: trackPage)
    }

    private var trackGridWidth: CGFloat {
        let columnCount = CGFloat(trackPageSize)
        return columnCount * trackColumnWidth + max(0, columnCount - 1) * gridSpacing
    }

    private var visibleTrackSlots: [StepSequenceTrack?] {
        let visibleTracks = scopedLayerTracks
        let startIndex = min(trackPage * trackPageSize, visibleTracks.count)
        let pagedTracks = Array(visibleTracks.dropFirst(startIndex).prefix(trackPageSize))
        return pagedTracks.map(Optional.some) + Array(repeating: nil, count: max(0, trackPageSize - pagedTracks.count))
    }

    private var scopedLayerTracks: [StepSequenceTrack] {
        let scopedTrackIDs = phraseLayerTrackScopeIDs
        return tracks.filter { scopedTrackIDs.contains($0.id) }
    }

    private var phraseLayerTrackScopeIDs: [UUID] {
        let orderedTrackIDs = tracks.map(\.id)
        let requestedIDs: Set<UUID>
        switch trackScopeChoice {
        case .all:
            return orderedTrackIDs
        case .currentSelection:
            requestedIDs = session.performTrackScope
        case .group(let slotIndex):
            guard session.store.performanceTrackGroups.indices.contains(slotIndex),
                  let group = session.store.performanceTrackGroups[slotIndex]
            else { return orderedTrackIDs }
            requestedIDs = Set(group.memberIDs)
        }
        return orderedTrackIDs.filter { requestedIDs.contains($0) }
    }

    private var selectedPhraseForEditing: PhraseModel {
        session.phraseWithPerformOverlay(session.store.selectedPhrase)
    }

    private var legacyVisualWorkspaceTab: String {
        phraseTab == .values ? "globalApply" : phraseTab.rawValue
    }

    private var phraseCellSelectionContext: PhraseCellSelectionContext {
        PhraseCellSelectionContext(
            phraseID: session.store.selectedPhraseID,
            layerID: activeMatrixLayer?.id,
            liveTrackIDs: scopedLayerTracks.map(\.id),
            isCellSurfaceVisible: phraseTab == .layers
        )
    }

    private var documentEditRevision: PhraseDocumentEditRevision {
        PhraseDocumentEditRevision(
            selectedPhraseID: session.store.selectedPhraseID,
            phraseIDs: phrases.map(\.id),
            activeLayerID: activeMatrixLayer?.id,
            cellSelection: phraseLayerSelection,
            usesCellTarget: usesPhraseCellDocumentEditTarget
        )
    }

    var body: some View {
        // The top-nav pill already names this page; the panel renders no
        // header of its own (ux-canon rule 1).
        let content = phraseWorkspacePanel
        // Standard workspace surface inset (matches Tracks/Mixer/Track/Drum):
        // every page roots its content at the shared workspace inset so the
        // left/top/bottom gap from the nav chrome is identical across surfaces.
        .padding(StudioMetrics.Spacing.workspaceInset)
        .sheet(item: $editingCellTarget) { target in
            PhraseCellEditorSheet(
                target: target,
                accent: layerAccent(target.layerID)
            )
            .presentationBackground(.clear)
        }
        .sheet(item: $finiteChoiceTarget) { target in
            PhraseFiniteChoiceSheet(
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
        .sheet(isPresented: $isPresentingGlobalApplyTrackSelector) {
            phraseTrackScopeSheet
                .presentationBackground(.clear)
        }
        .onAppear {
            reconcileSelectedLayer()
            clampTrackPage()
            applyVisualControlsOpenIndex()
            consumePendingPhrasePerform()
            for command in VisualScenarioCommandRunner.drainPendingPhraseMatrixCommands() {
                applyMatrixVisualCommand(command)
            }
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: session.pendingPhrasePerform) {
            // The view may already be mounted (e.g. navigated from Tracks while
            // Phrase is the live section), so consume the pending target here too.
            consumePendingPhrasePerform()
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
            reconcilePhraseCellSelection()
            applyVisualControlsOpenIndex()
        }
        .onChange(of: tracks.map(\.id)) {
            dismissInvalidEditorTarget()
            reconcilePhraseCellSelection()
        }
        .onChange(of: layers.map(\.id)) {
            dismissInvalidEditorTarget()
            reconcileSelectedLayer()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: selectedLayerID) {
            reconcilePhraseCellSelection()
            postRenderedMatrixVisualState(isVisible: true)
        }
        .onChange(of: performanceLayerSelection.mode, handlePerformanceLayerModeChange)
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

        return content
        .onChange(of: phraseCellSelectionContext) {
            if phraseCellSelectionContext.isCellSurfaceVisible {
                reconcilePhraseCellSelection()
            } else {
                phraseLayerSelection.clear()
            }
        }
        .documentEditTarget(
            isActive: true,
            revision: documentEditRevision,
            makeTarget: makeDocumentEditTarget
        )
    }

    private var phraseWorkspacePanel: some View {
        StudioPanel(
            title: "Phrase Matrix",
            accent: activeLayerAccent,
            showsHeader: false,
            contentPadding: 0
        ) {
            VStack(alignment: .leading, spacing: 8) {
                phraseTabBar
                phrasePerformanceShell
                phraseTabContent
            }
        }
    }

    private func handlePerformanceLayerModeChange() {
        if let layerID = performanceLayerSelection.mode.phraseLayerID,
           matrixSelectableLayers.contains(where: { $0.id == layerID }) {
            selectedLayerID = layerID
        }
        performanceLayerSelection.reconcileVariant(
            availableVariantLabels: phraseLocalPerformanceLayerOptions
                .filter { $0.mode == performanceLayerSelection.mode }
                .compactMap(\.variantLabel)
        )
        reconcilePhraseCellSelection()
        postRenderedMatrixVisualState(isVisible: true)
    }

    @ViewBuilder
    private var phraseTabContent: some View {
        switch phraseTab {
        case .layers:
            selectedPhraseLayerMatrix
        case .values:
            globalApplySurface
        case .scenes:
            phraseScenesSurface
        }
    }

    private func makeDocumentEditTarget() -> DocumentEditCommandController.Target {
        usesPhraseCellDocumentEditTarget
            ? phraseCellDocumentEditTarget()
            : phraseDocumentEditTarget(session: session)
    }

    private var phrasePerformanceShell: some View {
        // The orange perform-copy bar carries the perform controls and — on the
        // LAYERS tab only — the PHRASE LAYER selector + VALUE/AUTOMATION cell
        // tools. Bug 20260620-135607: the truncated "Phrase…" title is gone;
        // the top-nav pill already names the page. When the layer selector is
        // open (bug 20260620-135925), its grid lives INSIDE this box so the
        // connection to the PATTERN/layer button stays clear.
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                if phraseTab == .scenes {
                    phraseSceneViewModeControl
                }

                if phraseTab == .layers {
                    shellLayerControls
                }

                // The track scope is useful in both layer orientations: By
                // Track filters which tracks are shown; By Value chooses which
                // tracks receive the same value.
                if phraseTab == .layers || phraseTab == .values {
                    globalApplyTrackScopeButton
                }

                // Timing controls only exist in perform mode and sit on the
                // left before the Spacer, so they push nothing around.
                if session.workspaceMode == .perform {
                    phraseLatchTimingControls
                }

                Spacer(minLength: 8)

                // Capture/Discard sit immediately to the LEFT of Perform and
                // only appear when there's a live perform copy to act on —
                // i.e. perform is on and changes have been staged
                // (bug 20260623-130017). Otherwise they're hidden entirely.
                if phrasePerformActionAvailability.canCapture {
                    phraseCaptureActions
                }

                phrasePerformToggle
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(phraseShellAccent.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("phrase-performance-shell")
    }

    // Well strokes / container chrome carry ONLY the phrase surface accent.
    private var phraseShellAccent: Color {
        phraseTab.accent
    }

    private var phrasePerformToggle: some View {
        Button {
            session.workspaceMode = session.workspaceMode == .perform ? .setup : .perform
        } label: {
            // fixedSize: the shell HStack squeezed this control into a sliver
            // at the well's right edge, deforming the label into a vertical
            // letter stack (Rule 7, design review 08–11). The pill keeps its
            // natural width; flexible siblings compress instead.
            Text(session.workspaceMode == .perform ? "Perform On" : "Perform Off")
                .fixedSize()
                .studioText(.labelBold)
                .foregroundStyle(session.workspaceMode == .perform ? StudioTheme.background : StudioTheme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(session.workspaceMode == .perform ? StudioTheme.phraseAccent : StudioTheme.subtleFill, in: Capsule())
                .overlay(
                    Capsule()
                        .stroke(
                            session.workspaceMode == .perform ? Color.clear : StudioTheme.border,
                            lineWidth: StudioMetrics.borderWidth
                        )
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("phrase-perform-toggle")
        .help(session.workspaceMode == .perform ? "Turn off phrase perform copy editing" : "Edit a temporary phrase copy during performance")
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
                        .background(phraseLatchMode == mode ? StudioTheme.phraseAccent : StudioTheme.inset, in: Capsule())
                        .contentShape(Capsule())
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
                    .background(phraseLatchMode == .latched ? StudioTheme.subtleFill : StudioTheme.inset, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(phraseLatchMode == .latched ? StudioTheme.phraseAccent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
                    .contentShape(Capsule())
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
                    .background(phraseLatchMode == .latched ? StudioTheme.subtleFill : StudioTheme.inset, in: Capsule())
                    .overlay(
                        Capsule()
                            .stroke(phraseLatchMode == .latched && phraseLatchLengthBars != nil ? StudioTheme.phraseAccent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(phraseLatchMode != .latched)
            .help(phraseLatchMode == .latched ? "Latch can hold until changed or apply for 1, 2, 4, or 8 bars" : "Momentary changes do not use latch length")
        }
        .padding(3)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
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

    // Capture + Discard sit right next to Perform On — they're only useful
    // while perform is on and share its capsule grammar (bug 20260620-135423).
    // The caller only renders this row when there's a live copy to act on
    // (perform on + staged changes, bug 20260623-130017), so these buttons are
    // always actionable here. Capture is the primary phrase-accent action,
    // Discard is the outline-only secondary.
    private var phraseCaptureActions: some View {
        let availability = phrasePerformActionAvailability

        return HStack(spacing: 8) {
            Button {
                isPresentingPhraseCapture = true
            } label: {
                Text("Capture")
                    .fixedSize()
                    .studioText(.labelBold)
                    .foregroundStyle(availability.canCapture ? StudioTheme.background : StudioTheme.mutedText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(availability.canCapture ? StudioTheme.phraseAccent : StudioTheme.subtleFill, in: Capsule())
                    .overlay(Capsule().stroke(availability.canCapture ? StudioTheme.phraseAccent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!availability.canCapture)
            .accessibilityIdentifier("phrase-capture")
            .help(availability.captureHelp)

            Button {
                session.revertPhrasePerformOverlay()
            } label: {
                // Neutral chrome for the secondary action.
                Text("Discard")
                    .fixedSize()
                    .studioText(.labelBold)
                    .foregroundStyle(availability.canDiscard ? StudioTheme.text : StudioTheme.mutedText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(StudioTheme.subtleFill, in: Capsule())
                    .overlay(Capsule().stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!availability.canDiscard)
            .accessibilityIdentifier("phrase-discard")
            .help(availability.discardHelp)
        }
    }

    private var phrasePerformActionAvailability: PhrasePerformActionAvailabilityPresentation {
        PhrasePerformActionAvailabilityPresentation(
            isPerformMode: session.workspaceMode == .perform,
            hasLiveCopy: session.phrasePerformOverlay.hasLiveCopy,
            hasChanges: session.phrasePerformOverlay.isDirty
        )
    }

    private var phraseTabBar: some View {
        HStack(spacing: gridSpacing) {
            ForEach(PhraseWorkspaceTab.allCases) { tab in
                Button {
                    phraseTab = tab
                    if tab == .layers { phraseLayerEditMode = .byTrack }
                    if tab == .values { phraseLayerEditMode = .byValue }
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
                    .background(phraseTab == tab ? tab.accent : StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
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

    // Macros | Slots switch for the SCENES tab: the SAME shared segmented
    // pill as the layer-mode switch, so every phrase-workspace mode switch
    // shares one idiom.
    private var phraseSceneViewModeControl: some View {
        StudioModeSegmentedPill(
            segments: PhraseSceneViewMode.allCases.map { mode in
                StudioModeSegmentedPillSegment(
                    mode: mode,
                    symbolName: mode.symbolName,
                    label: mode.label,
                    help: mode.help,
                    accessibilityIdentifier: "phrase-scene-view-mode-\(mode.rawValue)"
                )
            },
            selection: phraseSceneViewMode,
            accent: StudioTheme.phraseAccent,
            accessibilityIdentifier: "phrase-scene-view-mode-control"
        ) { mode in
            phraseSceneViewMode = mode
        }
    }

    // Track groups are a fixed 16-slot bank, so the trigger opens the same
    // matrix-style StudioModal used when creating a group rather than falling
    // back to native macOS menu chrome.
    private var globalApplyTrackScopeButton: some View {
        Button {
            isPresentingGlobalApplyTrackSelector = true
            postRenderedMatrixVisualState(isVisible: true)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.3.sequence.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(phraseTrackScopeLabel)
                    .studioText(.labelBold)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .foregroundStyle(StudioTheme.text)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(
                StudioTheme.subtleFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.chip, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("phrase-layer-track-scope-button")
        .help(phraseTab == .layers ? "Choose the tracks visible in Layer" : "Choose the tracks receiving Values changes")
    }

    private var phraseTrackScopeLabel: String {
        switch trackScopeChoice {
        case .all:
            return "All Tracks"
        case .currentSelection:
            return "Current Selection"
        case .group(let index):
            guard session.store.performanceTrackGroups.indices.contains(index),
                  let group = session.store.performanceTrackGroups[index]
            else { return "All Tracks" }
            return "\(index + 1) · \(group.name)"
        }
    }

    private func applyTrackScopeChoice(_ choice: PhraseTrackScopeChoice) {
        trackScopeChoice = choice
        isPresentingGlobalApplyTrackSelector = false
        trackPage = 0
        postRenderedMatrixVisualState(isVisible: true)
    }

    private var phraseTrackScopeSheet: some View {
        StudioModal(
            title: "Choose Track Group",
            accent: StudioTheme.phraseAccent,
            minWidth: 520,
            onClose: {
                isPresentingGlobalApplyTrackSelector = false
                postRenderedMatrixVisualState(isVisible: true)
            }
        ) {
            VStack(alignment: .leading, spacing: StudioMetrics.Spacing.standard) {
                HStack(spacing: 10) {
                    phraseTrackScopeTopChoice(title: "All Tracks", choice: .all)
                    if !session.performTrackScope.isEmpty {
                        phraseTrackScopeTopChoice(title: "Current Selection", choice: .currentSelection)
                    }
                }

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(minimum: 86), spacing: 10), count: 4),
                    spacing: 10
                ) {
                    ForEach(0..<PerformanceTrackGroup.slotCount, id: \.self) { index in
                        phraseTrackScopeSlot(index)
                    }
                }
            }
            .accessibilityIdentifier("phrase-track-group-slot-matrix")
        }
    }

    private func phraseTrackScopeTopChoice(
        title: String,
        choice: PhraseTrackScopeChoice
    ) -> some View {
        let isSelected = trackScopeChoice == choice
        return Button {
            applyTrackScopeChoice(choice)
        } label: {
            Text(title)
                .studioText(.labelBold)
                .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.text)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(
                    isSelected ? StudioTheme.phraseAccent : StudioTheme.subtleFill,
                    in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(isSelected ? Color.clear : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func phraseTrackScopeSlot(_ index: Int) -> some View {
        let group = session.store.performanceTrackGroups[index]
        let isSelected = trackScopeChoice == .group(index)
        return Button {
            guard group != nil else { return }
            applyTrackScopeChoice(.group(index))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(index + 1)")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(isSelected ? StudioTheme.background : StudioTheme.phraseAccent)
                Text(group?.name ?? "Empty")
                    .studioText(.labelBold)
                    .foregroundStyle(isSelected ? StudioTheme.background : group == nil ? StudioTheme.mutedText : StudioTheme.text)
                    .lineLimit(1)
                if let group {
                    Text("\(group.memberIDs.count) track\(group.memberIDs.count == 1 ? "" : "s")")
                        .studioText(.micro)
                        .foregroundStyle(isSelected ? StudioTheme.background.opacity(0.75) : StudioTheme.mutedText)
                }
            }
            .padding(StudioMetrics.Spacing.compact)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(
                isSelected ? StudioTheme.phraseAccent : StudioTheme.subtleFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(
                        isSelected ? Color.clear : group == nil ? StudioTheme.border : StudioTheme.phraseAccent,
                        lineWidth: StudioMetrics.borderWidth
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(group == nil)
        .accessibilityIdentifier("phrase-track-group-slot-\(index + 1)")
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
                phraseSceneSlot(scene: sceneA, slot: .a, isDominant: crossfader < 0.5)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                phraseSceneCrossfader(value: crossfader)
                    .frame(width: 180)

                phraseSceneSlot(scene: sceneB, slot: .b, isDominant: crossfader > 0.5)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
        scene: MasterBusScene,
        slot: ScenePerformSlotPickerRequest.Slot,
        isDominant: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(slot.title.uppercased())
                        .studioText(.micro)
                        .tracking(0.8)
                        .foregroundStyle(StudioTheme.phraseAccent)

                    Text(scene.name)
                        .studioText(.title)
                        .foregroundStyle(StudioTheme.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 8)

                Text("\(slot.shortTitle):\(sceneNumber(for: scene.id) ?? 0)")
                    .studioText(.labelBold)
                    .monospacedDigit()
                    .foregroundStyle(StudioTheme.background)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(StudioTheme.phraseAccent, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.badge, style: .continuous))
            }
            .padding(StudioMetrics.Spacing.comfortable)
            .background(
                StudioTheme.subtleFill,
                in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(isDominant ? StudioTheme.phraseAccent.opacity(StudioOpacity.mediumStroke) : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                setPhraseSceneCrossfader(slot == .a ? 0 : 1)
            }

            switch phraseSceneViewMode {
            case .macros:
                phraseSceneMacroGrid(scene)
            case .slots:
                phraseSceneSlotMatrix(slot: slot)
            }
        }
        .padding(StudioMetrics.Spacing.standard)
        .background(Color.clear, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.phraseAccent.opacity(StudioOpacity.hoverFill), lineWidth: StudioMetrics.borderWidth)
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
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
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
                MacroSlotKnobDescriptor(
                    identity: $0.id.uuidString,
                    displayName: $0.name,
                    valueRange: $0.target.valueRange
                )
            },
            value: macro.map { phraseSceneMacroValue($0, scene: scene) },
            accent: StudioTheme.phraseAccent,
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
                .foregroundStyle(StudioTheme.phraseAccent)
                .frame(width: 56, alignment: .center)

            HStack(spacing: 8) {
                Text("A")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.phraseAccent)
                    .frame(width: 14, alignment: .leading)

                StudioSlideControl(
                    value: value,
                    range: 0...1,
                    fillStyle: .fromLeading,
                    chrome: .roundedRectangle,
                    accent: StudioTheme.phraseAccent,
                    help: "Phrase scene crossfader",
                    accessibilityStep: 0.05,
                    onChange: setPhraseSceneCrossfader
                )
                .frame(height: 42)

                Text("B")
                    .studioText(.eyebrowBold)
                    .foregroundStyle(StudioTheme.phraseAccent)
                    .frame(width: 14, alignment: .trailing)
            }
        }
        .padding(StudioMetrics.Spacing.comfortable)
        .frame(maxWidth: .infinity)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .accessibilityIdentifier("phrase-scene-crossfader")
    }

    // Slots mode: fixed 4x4 numbered cells. Existing scenes are tap targets;
    // unused scene positions stay as dashed empty cells so the surface reads
    // as a matrix rather than a stack of scene cards.
    private func phraseSceneSlotMatrix(slot: ScenePerformSlotPickerRequest.Slot) -> some View {
        LazyVGrid(columns: sceneSlotMatrixColumns, spacing: 8) {
            let scenes = Array(session.store.masterBus.scenes.prefix(16))
            ForEach(0..<16, id: \.self) { index in
                if scenes.indices.contains(index) {
                    phraseSceneMatrixCell(scene: scenes[index], sceneNumber: index + 1, slot: slot)
                } else {
                    phraseSceneEmptyMatrixCell(sceneNumber: index + 1, accent: StudioTheme.phraseAccent)
                }
            }
        }
        .padding(StudioMetrics.Spacing.compact)
        .accessibilityIdentifier("phrase-scene-slot-matrix-\(slot.rawValue)")
    }

    private var sceneSlotMatrixColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 46), spacing: 8), count: 4)
    }

    private func phraseSceneMatrixCell(
        scene: MasterBusScene,
        sceneNumber: Int,
        slot: ScenePerformSlotPickerRequest.Slot
    ) -> some View {
        let selected = selectedPhraseSceneID(for: slot) == scene.id
        return Button {
            setPhraseScene(scene.id, for: slot)
        } label: {
            Text("\(sceneNumber)")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? StudioTheme.background : StudioTheme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(selected ? StudioTheme.phraseAccent : Color.clear, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                        .stroke(selected ? StudioTheme.phraseAccent : StudioTheme.border, lineWidth: selected ? 2 : StudioMetrics.borderWidth)
                )
        }
        .buttonStyle(.plain)
        .studioSelectOnRightClick {
            setPhraseScene(scene.id, for: slot)
            setPhraseSceneCrossfader(PhraseSceneHardSwitch.crossfaderValue(for: slot))
        }
        .help("\(slot.title): \(scene.name)")
        .accessibilityLabel("\(slot.title) scene \(sceneNumber), \(scene.name)")
    }

    private func phraseSceneEmptyMatrixCell(sceneNumber: Int, accent: Color) -> some View {
        Text("\(sceneNumber)")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(StudioTheme.mutedText.opacity(0.45))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.clear, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                    .stroke(accent.opacity(StudioOpacity.hoverFill), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: StudioAddCard.dashPattern))
            )
            .accessibilityLabel("Empty scene slot \(sceneNumber)")
    }

    private func phraseSceneSlotPickerSheet(_ request: ScenePerformSlotPickerRequest) -> some View {
        StudioModal(
            title: request.slot.title,
            minWidth: 560,
            minHeight: 430,
            onClose: { phraseSceneSlotPickerRequest = nil }
        ) {
            ScrollView {
                LazyVGrid(columns: scenePickerColumns, spacing: 12) {
                    ForEach(session.store.masterBus.scenes) { scene in
                        phraseScenePickerCard(scene, slot: request.slot)
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

    // Shared scene card: used by the Choose modal and the inline Slots matrix.
    private func phraseScenePickerCard(_ scene: MasterBusScene, slot: ScenePerformSlotPickerRequest.Slot) -> some View {
        let selected = selectedPhraseSceneID(for: slot) == scene.id
        let sceneNumber = sceneNumber(for: scene.id) ?? 0
        return Button {
            setPhraseScene(scene.id, for: slot)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(sceneNumber)")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(selected ? StudioTheme.phraseAccent : StudioTheme.text)
                    Spacer()
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StudioTheme.phraseAccent)
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
            .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(selected ? StudioTheme.phraseAccent.opacity(StudioOpacity.ghostStroke) : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private func sceneNumber(for sceneID: UUID) -> Int? {
        session.store.masterBus.scenes.firstIndex { $0.id == sceneID }.map { $0 + 1 }
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

    // Compact layer controls that live INSIDE the orange perform-copy bar on
    // the LAYERS tab. The selected layer pill carries the value context; copy /
    // paste / automation live on the cells' right-click menu.
    @ViewBuilder
    private var shellLayerControls: some View {
        if phraseTab == .layers {
            HStack(spacing: 8) {
                phraseLayerSelectorButton
                    .frame(width: 132)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var phraseLayerSelectorButton: some View {
        Button {
                isPresentingPerformanceLayerSelection = true
            } label: {
                HStack(spacing: 6) {
                    // Bold-flat pass: solid accent circle with dark glyph.
                    Image(systemName: performanceLayerSelection.mode.symbolName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudioTheme.background)
                        .frame(width: 22, height: 22)
                        .background(activeLayerAccent, in: Circle())

                    Text(performanceLayerSelection.activeLabel.uppercased())
                        .studioText(.microEmphasis)
                        .tracking(0.6)
                        .foregroundStyle(activeLayerAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: isPresentingPerformanceLayerSelection ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                        .stroke(activeLayerAccent.opacity(StudioOpacity.subtleStroke), lineWidth: StudioMetrics.borderWidth)
                )
                .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("phrase-layer-selector")
            .help("Choose the Phrase performance layer")
    }

    private func phraseCellToolButton(_ tool: PhraseCellTool) -> some View {
        Button {
            phraseCellTool = tool
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tool.symbolName)
                    .font(.system(size: 11, weight: .bold))
                Text(tool.label.uppercased())
                    .studioText(.microEmphasis)
                    .tracking(0.8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(phraseCellTool == tool ? StudioTheme.background : StudioTheme.mutedText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(phraseCellTool == tool ? activeLayerAccent : StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(phraseCellTool == tool ? activeLayerAccent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
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
        guard let selectedIndex = scopedLayerTracks.firstIndex(where: { $0.id == session.store.selectedTrackID }) else {
            clampTrackPage()
            return
        }
        trackPage = min(max(selectedIndex / trackPageSize, 0), trackPageCount - 1)
    }

    private func clampTrackPage() {
        trackPage = min(max(trackPage, 0), trackPageCount - 1)
    }

    /// Consume a pending Tracks→Phrase navigation request (set by the tracks
    /// actions nav): open the requested tab/mode and seed the shared layer track
    /// scope from the selection. The perform scope itself is already set on the
    /// session. Cleared once applied so it fires once.
    private func consumePendingPhrasePerform() {
        guard let pending = session.pendingPhrasePerform else { return }
        phraseTab = pending.tab
        if let layerEditMode = pending.layerEditMode {
            phraseLayerEditMode = layerEditMode
            phraseTab = layerEditMode == .byTrack ? .layers : .values
        }
        if phraseTab != .layers {
            isPresentingPerformanceLayerSelection = false
        }
        // Re-assert the perform scope as the view mounts so it is authoritative
        // for the phrase surfaces regardless of any intervening navigation.
        session.performTrackScope = pending.trackIDs
        let matchingGroupIndex = session.store.performanceTrackGroups.firstIndex { group in
            guard let group else { return false }
            return Set(group.memberIDs) == pending.trackIDs
        }
        trackScopeChoice = matchingGroupIndex.map(PhraseTrackScopeChoice.group) ?? .currentSelection
        clampTrackPage()
        session.pendingPhrasePerform = nil
        postRenderedMatrixVisualState(isVisible: true)
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
            return
        }

        if command.hasPrefix("tab:") {
            let rawTab = String(command.dropFirst("tab:".count))
            if rawTab == "globalApply" {
                phraseTab = .values
                phraseLayerEditMode = .byValue
                isPresentingPerformanceLayerSelection = false
                postRenderedMatrixVisualState(isVisible: true)
            } else if let tab = PhraseWorkspaceTab(rawValue: rawTab) {
                phraseTab = tab
                if tab == .layers { phraseLayerEditMode = .byTrack }
                if tab == .values { phraseLayerEditMode = .byValue }
                if tab != .layers {
                    isPresentingPerformanceLayerSelection = false
                }
                postRenderedMatrixVisualState(isVisible: true)
            }
            return
        }

        if command.hasPrefix("cell-tool:") {
            let rawTool = String(command.dropFirst("cell-tool:".count))
            if let tool = PhraseCellTool(rawValue: rawTool) {
                phraseCellTool = tool
                postRenderedMatrixVisualState(isVisible: true)
            }
            return
        }

        if command == "global-apply-track-selector:open" {
            phraseTab = .values
            phraseLayerEditMode = .byValue
            trackScopeChoice = session.store.performanceTrackGroups.firstIndex(where: { $0 != nil })
                .map(PhraseTrackScopeChoice.group) ?? .all
            isPresentingGlobalApplyTrackSelector = true
            postRenderedMatrixVisualState(isVisible: true)
            return
        }

        if command == "global-apply-track-selector:close" {
            isPresentingGlobalApplyTrackSelector = false
            postRenderedMatrixVisualState(isVisible: true)
            return
        }

        // QA: scope the Phrase layer surface to the first N tracks.
        if command.hasPrefix("global-apply-select:"),
           let rawCount = command.split(separator: ":").last,
           let count = Int(rawCount) {
            phraseTab = .values
            phraseLayerEditMode = .byValue
            isPresentingGlobalApplyTrackSelector = false
            session.performTrackScope = Set(tracks.prefix(max(0, count)).map(\.id))
            trackScopeChoice = .currentSelection
            postRenderedMatrixVisualState(isVisible: true)
            return
        }

        // QA: switch the SCENES perform surface between Macros | Slots view
        // modes (the perform-bar segmented pill).
        if command.hasPrefix("scene-view-mode:") {
            let rawMode = String(command.dropFirst("scene-view-mode:".count))
            if let mode = PhraseSceneViewMode(rawValue: rawMode) {
                phraseTab = .scenes
                phraseSceneViewMode = mode
            }
            postRenderedMatrixVisualState(isVisible: true)
            return
        }

        if command.hasPrefix("scene-select:") {
            let rawSlot = String(command.dropFirst("scene-select:".count))
            if rawSlot == "close" {
                phraseSceneSlotPickerRequest = nil
            } else if let slot = ScenePerformSlotPickerRequest.Slot(rawValue: rawSlot) {
                phraseTab = .scenes
                phraseSceneViewMode = .slots
                setPhraseSceneCrossfader(slot == .a ? 0 : 1)
                phraseSceneSlotPickerRequest = nil
            }
            postRenderedMatrixVisualState(isVisible: true)
            return
        }

        if command == "phrase-capture:open" {
            isPresentingGlobalApplyTrackSelector = false
            isPresentingPhraseCapture = session.phrasePerformOverlay.hasLiveCopy
            postRenderedMatrixVisualState(isVisible: true)
            return
        }

        if command == "phrase-capture:close" {
            isPresentingPhraseCapture = false
            postRenderedMatrixVisualState(isVisible: true)
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
                "workspaceTab": isVisible ? legacyVisualWorkspaceTab : "none",
                "phraseLayerEditMode": isVisible ? phraseLayerEditMode.rawValue : "none",
                "cellTool": isVisible ? phraseCellTool.rawValue : "none",
                "globalApplyTrackSelectorVisible": isVisible && isPresentingGlobalApplyTrackSelector,
                "captureVisible": isVisible && isPresentingPhraseCapture,
                "sceneSelectVisible": isVisible && phraseSceneSlotPickerRequest != nil,
                "sceneViewMode": isVisible ? phraseSceneViewMode.rawValue : "none",
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
            if NSEvent.modifierFlags.contains(.option) {
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

    private func handlePhraseLayerCellTap(on phraseID: UUID, trackID: UUID) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            applyPhraseLayerSelectionGesture(.additiveToggle, trackID: trackID)
            session.setSelectedPhraseAndTrackID(phraseID: phraseID, trackID: trackID)
            return
        }

        if performanceLayerSelection.mode == .noteRepeat {
            toggleNoteRepeat(trackIDs: [trackID])
        } else {
            handleSingleTap(on: phraseID, trackID: trackID)
        }
    }

    private func selectPatternSlot(_ slotIndex: Int, phraseID: UUID, trackID: UUID) {
        guard let activeMatrixLayer, activeMatrixLayer.valueType == .patternIndex,
              let phrase = phrases.first(where: { $0.id == phraseID })
        else {
            return
        }
        guard let selectedSlotIndex = TrackPerformPatternMiniCellInteraction.selectedSlotAfterMiniCellClick(
            requestedSlotIndex: slotIndex
        ) else {
            return
        }
        session.setSelectedPhraseAndTrackID(phraseID: phraseID, trackID: trackID)

        let displayedPhrase = session.phraseWithPerformOverlay(phrase)
        if PhrasePerformTimingPolicy.usesQuantisedLayerArming(
            layerID: activeMatrixLayer.id,
            latchMode: phraseLatchMode,
            sessionArmingActive: session.isQuantisedPerformToggleArmingActive
        ) {
            session.selectQuantisedPatternIndex(
                slotIndex: selectedSlotIndex,
                trackIDs: [trackID],
                basisPhrase: displayedPhrase,
                lengthBars: phraseLatchLengthBars
            )
            return
        }

        session.setPhraseCell(
            .single(.index(selectedSlotIndex)),
            layerID: activeMatrixLayer.id,
            trackIDs: [trackID],
            phraseID: phraseID
        )
    }

    private func openFiniteChoicePicker(phraseID: UUID, trackID: UUID) {
        guard let activeMatrixLayer,
              activeMatrixLayer.valueType == .patternIndex
        else {
            if activeMatrixLayer == nil {
                isPresentingPerformanceLayerSelection = true
            }
            return
        }

        session.setSelectedPhraseAndTrackID(phraseID: phraseID, trackID: trackID)
        finiteChoiceTarget = PhraseFiniteChoiceTarget(
            phraseID: phraseID,
            trackID: trackID,
            layerID: activeMatrixLayer.id
        )
    }

    /// Option-click: toggle the value, write it as an explicit value on THIS
    /// phrase, and convert every *following* phrase's cell to inherit it.
    /// Inheritance is forward-only — earlier phrases are never touched, and the
    /// clicked phrase + its following inheritors all resolve to the new value
    /// (the nearest preceding explicit value in song order).
    private func cascadeBooleanValue(phraseID: UUID, trackID: UUID) {
        guard let layer = activeMatrixLayer,
              layer.valueType == .boolean,
              let startIndex = phrases.firstIndex(where: { $0.id == phraseID })
        else {
            return
        }

        let inherited = inheritedDefaults(for: phraseID)
        let phrase = phrases[startIndex]
        let resolvedValue = phrase.resolvedValue(
            for: layer,
            trackID: trackID,
            stepIndex: 0,
            inherited: inherited
        )
        let toggledValue = toggledBooleanValue(resolvedValue, for: layer)

        // Anchor the cascade on the clicked phrase as an explicit value.
        session.setPhraseCell(
            .single(toggledValue),
            layerID: layer.id,
            trackIDs: [trackID],
            phraseID: phraseID
        )
        // Following phrases inherit it forward-only.
        for followingPhrase in phrases[(startIndex + 1)...] {
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

    private var usesPhraseCellDocumentEditTarget: Bool {
        phraseTab == .layers
            && activeMatrixLayer != nil
            && !phraseLayerSelection.isEmpty
    }

    private func selectPhraseLayerTrack(_ trackID: UUID, additive: Bool) {
        guard let activeMatrixLayer else { return }
        phraseLayerSelection.select(
            phraseID: session.store.selectedPhraseID,
            layerID: activeMatrixLayer.id,
            trackID: trackID,
            additive: additive
        )
        session.setSelectedTrackID(trackID)
    }

    private func applyPhraseLayerSelectionGesture(
        _ gesture: StudioSelectionGesture,
        trackID: UUID
    ) {
        guard let activeMatrixLayer else { return }
        phraseLayerSelection.applySelectionGesture(
            gesture,
            phraseID: session.store.selectedPhraseID,
            layerID: activeMatrixLayer.id,
            trackID: trackID
        )
        session.setSelectedTrackID(trackID)
    }

    private func phraseLayerSingleSelectionID(fallbackTrackID: UUID) -> UUID? {
        if phraseLayerSelection.count == 1 {
            return phraseLayerSelection.first
        }
        if phraseLayerSelection.isEmpty {
            return fallbackTrackID
        }
        return nil
    }

    private func reconcilePhraseCellSelection() {
        phraseLayerSelection.reconcile(
            phraseID: session.store.selectedPhraseID,
            layerID: activeMatrixLayer?.id,
            liveTrackIDs: scopedLayerTracks.map(\.id)
        )
    }

    private func phraseCellDocumentEditTarget() -> DocumentEditCommandController.Target {
        .init(
            canCopy: {
                guard let activeMatrixLayer else { return false }
                return !phraseLayerSelection.matchingTrackIDs(
                    phraseID: session.store.selectedPhraseID,
                    layerID: activeMatrixLayer.id,
                    liveTrackIDs: scopedLayerTracks.map(\.id)
                ).isEmpty
            },
            canClear: { !phraseLayerSelection.isEmpty },
            isPasteCompatible: { payload in
                guard payload.domain == .phraseCells,
                      let clipboard = payload.value(as: PhraseCellDocumentEditClipboard.self),
                      let activeMatrixLayer,
                      clipboard.isCompatible(with: activeMatrixLayer.id)
                else { return false }
                return !phraseLayerSelection.matchingTrackIDs(
                    phraseID: session.store.selectedPhraseID,
                    layerID: activeMatrixLayer.id,
                    liveTrackIDs: scopedLayerTracks.map(\.id)
                ).isEmpty
            },
            copy: {
                guard let activeMatrixLayer,
                      let phrase = session.store.phrases.first(where: { $0.id == session.store.selectedPhraseID })
                else { return nil }
                let matchingIDs = phraseLayerSelection.matchingTrackIDs(
                    phraseID: phrase.id,
                    layerID: activeMatrixLayer.id,
                    liveTrackIDs: scopedLayerTracks.map(\.id)
                )
                guard let trackID = matchingIDs.first else { return nil }
                let inherited = inheritedDefaults(for: phrase.id)
                return .init(
                    domain: .phraseCells,
                    snapshot: PhraseCellDocumentEditClipboard(
                        layerID: activeMatrixLayer.id,
                        cell: .single(
                            phrase.resolvedValue(
                                for: activeMatrixLayer,
                                trackID: trackID,
                                stepIndex: 0,
                                inherited: inherited
                            )
                        )
                    )
                )
            },
            paste: { payload in
                guard let clipboard = payload.value(as: PhraseCellDocumentEditClipboard.self),
                      let activeMatrixLayer,
                      clipboard.isCompatible(with: activeMatrixLayer.id)
                else { return }
                let phraseID = session.store.selectedPhraseID
                let targetIDs = phraseLayerSelection.matchingTrackIDs(
                    phraseID: phraseID,
                    layerID: activeMatrixLayer.id,
                    liveTrackIDs: scopedLayerTracks.map(\.id)
                )
                guard !targetIDs.isEmpty else { return }
                session.setPhraseCell(
                    clipboard.cell,
                    layerID: activeMatrixLayer.id,
                    trackIDs: targetIDs,
                    phraseID: phraseID
                )
            },
            clearSelection: {
                phraseLayerSelection.clear()
            }
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
                    .fill(presentation.isEnabled ? StudioTheme.subtleFill : StudioTheme.disabledSubtleFill)
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

    @ViewBuilder
    private var selectedPhraseLayerMatrix: some View {
        if isPresentingPerformanceLayerSelection {
            performanceLayerSelectionGrid
                .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
        } else if performanceLayerSelection.mode == .stepOrder {
            phraseStepOrderToggleSurface
                .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading)
        } else {
            // Size the track columns to the width the panel actually hands us
            // so a full page of columns fits inside the page without a clipped
            // partial column running off the right edge (bug 20260620-135607).
            GeometryReader { proxy in
                let columnWidth = fittedTrackColumnWidth(forAvailableWidth: proxy.size.width)
                matrixGrid(trackColumnWidth: columnWidth)
                    .frame(width: proxy.size.width, alignment: .leading)
            }
            .frame(minHeight: 280)
        }
    }

    private func matrixGrid(trackColumnWidth _: CGFloat) -> some View {
        // By Track layer matrix: the SELECTED phrase's per-track cells, each
        // showing that track's value for the active layer, as a full-width
        // wrapping grid — no track headers, no paging arrows. Phrases-as-rows is
        // the Song view's phrase matrix, not this (bug 20260623-134959).
        let activeLayer = activeMatrixLayer
        let accent = activeLayerAccent
        let selectedTrackID = session.store.selectedTrackID
        let displayedPhrase = selectedPhraseForEditing
        let rowInherited = inheritedDefaults(for: displayedPhrase.id)
        // Standard 8-column matrix grid (always 8 columns, full or not).
        let columns = StudioMetrics.Grid.matrixColumns(spacing: gridSpacing)
        return ScrollView(.vertical) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                ForEach(scopedLayerTracks, id: \.id) { track in
                    let renderedCell = activeLayer.map { displayedPhrase.cell(for: $0.id, trackID: track.id) }
                    let cellIsSelected = phraseLayerSelection.contains(track.id) || track.id == selectedTrackID
                    let trackAccent = StudioTheme.trackAccent(for: track, groups: session.store.trackGroups)
                    Group {
                        if performanceLayerSelection.mode == .noteRepeat {
                            PhrasePerformanceToggleCell(
                                stateLabel: noteRepeatStateLabel(trackID: track.id),
                                detail: track.name,
                                isAvailable: session.isNoteRepeatAvailable(trackID: track.id),
                                isActive: isSelectedNoteRepeatActive(trackID: track.id),
                                accent: accent,
                                trackAccent: trackAccent
                            )
                        } else if let activeLayer {
                            PhraseGridCell(
                                layer: activeLayer,
                                cell: renderedCell ?? .inheritDefault,
                                phrase: displayedPhrase,
                                track: track,
                                isSelected: cellIsSelected,
                                accent: accent,
                                trackAccent: trackAccent,
                                inherited: rowInherited,
                                onSelectPatternSlot: { slotIndex in
                                    selectPatternSlot(slotIndex, phraseID: displayedPhrase.id, trackID: track.id)
                                }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .modifier(
                        PhraseGridCellTapModifier(
                            isEnabled: performanceLayerSelection.mode == .noteRepeat
                                || activeLayer.map(TrackPerformPatternMiniCellInteraction.shouldCycleFromCardBackground) == true
                        ) {
                            handlePhraseLayerCellTap(on: displayedPhrase.id, trackID: track.id)
                        }
                    )
                    .simultaneousGesture(
                        scalarDragGesture(phrase: displayedPhrase, track: track, layer: activeLayer)
                    )
                    .studioSelectionGesture { gesture in
                        guard activeLayer != nil else {
                            if gesture == .singleSelection,
                               performanceLayerSelection.mode != .noteRepeat {
                                openFiniteChoicePicker(phraseID: displayedPhrase.id, trackID: track.id)
                            }
                            return
                        }
                        applyPhraseLayerSelectionGesture(gesture, trackID: track.id)
                        session.setSelectedPhraseAndTrackID(phraseID: displayedPhrase.id, trackID: track.id)
                    }
                    .contextMenu {
                        if activeLayer != nil {
                            Button("Select") {
                                selectPhraseLayerTrack(track.id, additive: false)
                            }
                            Button("Add to Selection") {
                                selectPhraseLayerTrack(track.id, additive: true)
                            }
                            if phraseLayerSingleSelectionID(fallbackTrackID: track.id) != nil {
                                Divider()
                                Button("Automation") {
                                    openCellEditor(
                                        phraseID: displayedPhrase.id,
                                        trackID: phraseLayerSingleSelectionID(fallbackTrackID: track.id) ?? track.id
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
    }

    /// Shrink the track columns just enough that a full page (gutters +
    /// spacing + every column) fits the available width; never grow past the
    /// natural width, and keep a sane floor so cells stay legible (bug
    /// 20260620-135607). If the floor still overflows the grid scrolls.
    private func fittedTrackColumnWidth(forAvailableWidth availableWidth: CGFloat) -> CGFloat {
        guard availableWidth > 0 else { return trackColumnWidth }
        let columnCount = CGFloat(trackPageSize)
        let fixedWidth = matrixGutterWidth * 2 + gridSpacing * (columnCount + 1)
        let widthForColumns = availableWidth - fixedWidth
        guard widthForColumns > 0 else { return minTrackColumnWidth }
        let fitted = widthForColumns / columnCount
        return min(trackColumnWidth, max(minTrackColumnWidth, fitted))
    }

    private let minTrackColumnWidth: CGFloat = 92

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

    private var selectedNoteRepeatInterval: NoteRepeatInterval? {
        performanceLayerSelection.variantLabel.flatMap(NoteRepeatInterval.init(rawValue:))
    }

    private func isSelectedNoteRepeatActive(trackID: UUID) -> Bool {
        guard let interval = selectedNoteRepeatInterval,
              let snapshot = engineController.noteRepeatRuntimeSnapshot(for: trackID)
        else { return false }
        return snapshot.interval == interval
    }

    private func areSelectedNoteRepeatsActive(
        trackIDs: [UUID],
        option: PerformanceLayerOption
    ) -> Bool {
        guard let label = option.variantLabel,
              let interval = NoteRepeatInterval(rawValue: label)
        else { return false }
        let availableTrackIDs = trackIDs.filter(session.isNoteRepeatAvailable(trackID:))
        guard !availableTrackIDs.isEmpty else { return false }
        return availableTrackIDs.allSatisfy {
            engineController.noteRepeatRuntimeSnapshot(for: $0)?.interval == interval
        }
    }

    private func noteRepeatStateLabel(trackID: UUID) -> String {
        guard session.isNoteRepeatAvailable(trackID: trackID) else { return "No Clip" }
        return isSelectedNoteRepeatActive(trackID: trackID) ? "On" : "Off"
    }

    private func toggleNoteRepeat(trackIDs: [UUID]) {
        guard let interval = selectedNoteRepeatInterval else { return }
        let availableTrackIDs = trackIDs.filter(session.isNoteRepeatAvailable(trackID:))
        guard !availableTrackIDs.isEmpty else { return }

        if availableTrackIDs.allSatisfy({
            engineController.noteRepeatRuntimeSnapshot(for: $0)?.interval == interval
        }) {
            availableTrackIDs.forEach { session.releaseNoteRepeat(trackID: $0) }
            return
        }

        availableTrackIDs.forEach {
            _ = session.setTrackNoteRepeatInterval(interval, trackID: $0)
        }
        availableTrackIDs.forEach {
            _ = session.engageNoteRepeat(trackID: $0)
        }
    }

    private func stepOrderMap(for option: PerformanceLayerOption) -> StepOrderMap? {
        guard option.mode == .stepOrder, let name = option.variantLabel else { return nil }
        return session.store.stepOrderMaps.first { $0.name == name && $0.isValid }
    }

    private func isSelectedStepOrderActive(option: PerformanceLayerOption) -> Bool {
        guard let map = stepOrderMap(for: option),
              selectedPhraseForEditing.stepOrderAssignment?.mapID == map.id
        else { return false }
        switch session.stepOrderToggleState(phraseID: selectedPhraseForEditing.id) {
        case .on, .pendingOn:
            return true
        case .off, .pendingOff, .unavailable:
            return false
        }
    }

    private func toggleStepOrder(option: PerformanceLayerOption) {
        guard let map = stepOrderMap(for: option) else { return }
        let phrase = selectedPhraseForEditing
        if phrase.stepOrderAssignment?.mapID != map.id {
            guard session.setStepOrderAssignment(phraseID: phrase.id, mapID: map.id, isEnabled: false) else { return }
            _ = session.requestPhraseStepOrderEnabled(true, phraseID: phrase.id)
            return
        }

        let shouldEnable: Bool
        switch session.stepOrderToggleState(phraseID: phrase.id) {
        case .on, .pendingOn:
            shouldEnable = false
        case .off, .pendingOff:
            shouldEnable = true
        case .unavailable:
            return
        }
        _ = session.requestPhraseStepOrderEnabled(shouldEnable, phraseID: phrase.id)
    }

    private var phraseStepOrderToggleSurface: some View {
        let option = PerformanceLayerOption(
            mode: .stepOrder,
            variantLabel: performanceLayerSelection.variantLabel
        )
        let isActive = isSelectedStepOrderActive(option: option)
        return LazyVGrid(columns: globalApplyColumns, alignment: .leading, spacing: 10) {
            Button {
                toggleStepOrder(option: option)
            } label: {
                PhrasePerformanceToggleCell(
                    stateLabel: isActive ? "On" : "Off",
                    detail: selectedPhraseForEditing.name,
                    isAvailable: stepOrderMap(for: option) != nil,
                    isActive: isActive,
                    accent: activeLayerAccent,
                    trackAccent: StudioTheme.phraseAccent
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("phrase-step-order-toggle")
        }
        .padding(.vertical, 2)
    }

    // Bug 20260620-140815: the orange wrapper + its padding are gone — the
    // scope bar and layer cards sit directly on the panel like the other tabs.
    private var globalApplySurface: some View {
        VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: globalApplyColumns, alignment: .leading, spacing: 10) {
                ForEach(globalApplyOptions) { option in
                    globalApplyActionCell(option)
                }
            }
        }
        .accessibilityIdentifier("phrase-global-apply-surface")
    }

    /// The resolved value across the scoped tracks for a layer, plus whether
    /// every scoped track currently agrees on it (unanimous) or diverges.
    private func globalApplyConsensus(for layer: PhraseLayerDefinition) -> (value: PhraseCellValue, isDivergent: Bool) {
        let phrase = selectedPhraseForEditing
        let values = globalApplyScopeTrackIDs.map { trackID in
            phrase.resolvedValue(for: layer, trackID: trackID, stepIndex: 0).normalized(for: layer)
        }
        guard let first = values.first else {
            return (.bool(false), false)
        }
        let isDivergent = values.contains { $0 != first }
        return (first, isDivergent)
    }

    @ViewBuilder
    private func globalApplyActionCell(_ option: PerformanceLayerOption) -> some View {
        if let layerID = option.mode.phraseLayerID,
           let layer = layers.first(where: { $0.id == layerID }) {
            globalApplyInteractiveCell(option, layer: layer)
        } else if option.mode == .noteRepeat {
            PerformanceLayerOptionCell(
                option: option,
                isSelected: areSelectedNoteRepeatsActive(trackIDs: globalApplyScopeTrackIDs, option: option),
                onTap: { applyGlobalOption(option) }
            )
        } else if option.mode == .stepOrder {
            PerformanceLayerOptionCell(
                option: option,
                isSelected: isSelectedStepOrderActive(option: option),
                onTap: { applyGlobalOption(option) }
            )
        } else {
            EmptyView()
        }
    }

    // Bug 20260620-140815 / consistency pass: the global-apply card renders its
    // value with the SAME PhraseCellPreview the Layers matrix uses, so a mute
    // value, a pattern value (the 4×4 slot matrix), and a scalar value (the
    // level well) look identical in both views. The card keeps its own framing
    // — the layer NAME label on top and a phrase-accent border when the scoped
    // tracks diverge ("mixed") — but the inner value cell is shared. Tapping
    // the whole card cycles/toggles via applyGlobalOption, the same write path
    // as before.
    @ViewBuilder
    private func globalApplyInteractiveCell(
        _ option: PerformanceLayerOption,
        layer: PhraseLayerDefinition
    ) -> some View {
        let consensus = globalApplyConsensus(for: layer)
        GlobalApplyLayerCard(
            option: option,
            layer: layer,
            value: consensus.value,
            isDivergent: consensus.isDivergent,
            summary: valueLabel(consensus.value, layer: layer),
            onApply: { applyGlobalOption(option) }
        )
    }


    private var phraseLocalPerformanceLayerOptions: [PerformanceLayerOption] {
        PerformanceLayerOption.phraseOptions(
            availableLayerIDs: Set(matrixSelectableLayers.map(\.id)),
            stepOrderMaps: session.store.stepOrderMaps,
            phraseStepCount: selectedPhraseForEditing.stepCount
        ).filter { option in
            option.mode != .noteRepeat
                || scopedLayerTracks.contains { session.isNoteRepeatAvailable(trackID: $0.id) }
        }
    }

    private var globalApplyOptions: [PerformanceLayerOption] {
        phraseLocalPerformanceLayerOptions
    }

    private var globalApplyColumns: [GridItem] {
        StudioMetrics.Grid.matrixColumns(spacing: 10, minimum: 84, maximum: 190)
    }

    private var globalApplyScopeTrackIDs: [UUID] {
        phraseLayerTrackScopeIDs
    }

    private func applyGlobalOption(_ option: PerformanceLayerOption) {
        if option.mode == .noteRepeat {
            selectPerformanceLayerOption(option)
            toggleNoteRepeat(trackIDs: globalApplyScopeTrackIDs)
            return
        }

        if option.mode == .stepOrder {
            selectPerformanceLayerOption(option)
            toggleStepOrder(option: option)
            return
        }

        guard let layerID = option.mode.phraseLayerID,
              let layer = layers.first(where: { $0.id == layerID }),
              let seedTrackID = globalApplyScopeTrackIDs.first
        else {
            return
        }

        selectPerformanceLayerOption(option)
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

    // The layer-selection grid replaces the track matrix in-place: no "CHOOSE
    // PHRASE LAYER" title and no separate box, so it reads as the same cell
    // field changing modes rather than a second surface.
    private var performanceLayerSelectionGrid: some View {
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
        .padding(.vertical, 2)
        .accessibilityIdentifier("phrase-performance-layer-selection-surface")
    }

    private var performanceLayerSelectionColumns: [GridItem] {
        StudioMetrics.Grid.matrixColumns(spacing: 10, minimum: 84, maximum: 190)
    }

    private func choosePerformanceLayer(_ option: PerformanceLayerOption) {
        selectPerformanceLayerOption(option)
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
        guard phraseLocalPerformanceLayerOptions.contains(where: {
            $0.mode == mode && $0.variantLabel == variantLabel
        }) else { return }
        let availableLabels = phraseLocalPerformanceLayerOptions
            .filter { $0.mode == mode }
            .compactMap(\.variantLabel)
        performanceLayerSelection.select(
            mode,
            variantLabel: variantLabel,
            availableVariantLabels: availableLabels.isEmpty ? nil : availableLabels
        )
        if let layerID = performanceLayerSelection.mode.phraseLayerID,
           matrixSelectableLayers.contains(where: { $0.id == layerID }) {
            selectedLayerID = layerID
        }
        isPresentingPerformanceLayerSelection = false
        postRenderedMatrixVisualState(isVisible: true)
    }

    private func selectPerformanceLayerOption(_ option: PerformanceLayerOption) {
        let availableLabels = phraseLocalPerformanceLayerOptions
            .filter { $0.mode == option.mode }
            .compactMap(\.variantLabel)
        performanceLayerSelection.select(
            option.mode,
            variantLabel: option.variantLabel,
            availableVariantLabels: availableLabels.isEmpty ? nil : availableLabels
        )
    }
}

struct PhraseFiniteChoiceTarget: Identifiable, Equatable {
    let phraseID: UUID
    let trackID: UUID
    let layerID: String

    var id: String {
        "\(phraseID.uuidString):\(trackID.uuidString):\(layerID)"
    }
}

private struct PhraseFiniteChoiceSheet: View {
    let target: PhraseFiniteChoiceTarget
    let accent: Color

    @Environment(SequencerDocumentSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    private var phrase: PhraseModel? {
        session.store.phrases.first(where: { $0.id == target.phraseID }).map(session.phraseWithPerformOverlay)
    }

    private var track: StepSequenceTrack? {
        session.store.tracks.first(where: { $0.id == target.trackID })
    }

    private var layer: PhraseLayerDefinition? {
        session.store.layer(id: target.layerID)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 64), spacing: 10), count: 4)
    }

    var body: some View {
        Group {
            if let phrase, let track, let layer {
                StudioModal(
                    title: layer.name,
                    subtitle: "\(phrase.name) • \(track.name)",
                    accent: accent,
                    minWidth: 420,
                    minHeight: 320,
                    onClose: { dismiss() }
                ) {
                    choiceGrid(phrase: phrase, track: track, layer: layer)
                }
            } else {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear {
                        dismiss()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func choiceGrid(
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) -> some View {
        let selectedIndex = selectedIndex(phrase: phrase, track: track, layer: layer)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(optionIndices(for: layer), id: \.self) { index in
                Button {
                    session.setPhraseCell(
                        .single(.index(index)),
                        layerID: layer.id,
                        trackIDs: [track.id],
                        phraseID: phrase.id
                    )
                    dismiss()
                } label: {
                    Text(optionLabel(index, layer: layer))
                        .studioText(.labelBold)
                        .foregroundStyle(index == selectedIndex ? StudioTheme.background : StudioTheme.text)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(index == selectedIndex ? accent : StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                                .stroke(index == selectedIndex ? accent : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(layer.name) \(optionLabel(index, layer: layer))")
            }
        }
    }

    private func selectedIndex(
        phrase: PhraseModel,
        track: StepSequenceTrack,
        layer: PhraseLayerDefinition
    ) -> Int? {
        guard case let .index(index) = phrase.resolvedValue(
            for: layer,
            trackID: track.id,
            stepIndex: 0
        ).normalized(for: layer) else {
            return nil
        }
        return index
    }

    private func optionIndices(for layer: PhraseLayerDefinition) -> [Int] {
        let lower = Int(layer.minValue.rounded(.up))
        let upper = Int(layer.maxValue.rounded(.down))
        guard lower <= upper else { return [] }
        return Array(lower...upper)
    }

    private func optionLabel(_ index: Int, layer: PhraseLayerDefinition) -> String {
        layer.valueType == .patternIndex ? "P\(index + 1)" : "\(index)"
    }
}

struct SongWorkspaceView: View {
    let onOpenPhrase: () -> Void
    @Environment(SequencerDocumentSession.self) private var session
    @Environment(EngineController.self) private var engineController

    private var phrases: [PhraseModel] {
        session.store.phrases
    }

    private var selectedPhrase: PhraseModel {
        session.store.selectedPhrase
    }

    private var tracks: [StepSequenceTrack] {
        session.store.tracks
    }

    private var layers: [PhraseLayerDefinition] {
        session.store.layers
    }

    private let phraseColumnWidth: CGFloat = 150
    private let trackColumnWidth: CGFloat = 126
    private let gridSpacing: CGFloat = 10

    /// The pattern layer is the canonical "what plays" surface, mirroring the
    /// original phrase matrix. Fall back to the first selectable layer (and
    /// finally the first layer) if a pattern layer can't be resolved.
    private var matrixLayer: PhraseLayerDefinition? {
        if let pattern = session.store.patternLayer {
            return pattern
        }
        let selectable = PhraseLayerSelectorPresentation.selectableLayers(from: layers)
        return selectable.first ?? layers.first
    }

    /// Forward-only inherited defaults so each row's cells display the value
    /// they will actually play, matching the engine compile path.
    private var inheritedDefaults: PhraseInheritedDefaults {
        PhraseInheritedDefaults.build(phrases: phrases, layers: layers)
    }

    var body: some View {
        StudioPanel(title: "Song", accent: StudioTheme.phraseAccent, showsHeader: false, contentPadding: 0) {
            VStack(alignment: .leading, spacing: 16) {
                songHeader
                phraseGrid
            }
        }
        .padding(StudioMetrics.Spacing.workspaceInset)
        .accessibilityIdentifier("song-workspace")
        .documentEditTarget(
            isActive: true,
            revision: PhraseDocumentEditRevision(
                selectedPhraseID: session.store.selectedPhraseID,
                phraseIDs: phrases.map(\.id),
                activeLayerID: nil,
                cellSelection: PhraseCellDocumentSelection(),
                usesCellTarget: false
            ),
            makeTarget: { phraseDocumentEditTarget(session: session) }
        )
    }

    private var songHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            // Canon creep purge (2026-07-02): the eyebrow stands alone — the
            // phrase list below is self-evidently the song's phrase chooser.
            Text("SONG")
                .studioText(.microEmphasis)
                .tracking(0.9)
                .foregroundStyle(StudioTheme.phraseAccent)

            Spacer(minLength: 12)

            songActionButton("Add Phrase", systemName: "plus") {
                session.insertPhrase(below: selectedPhrase.id)
            }

            songActionButton("Duplicate", systemName: "plus.square.on.square") {
                session.duplicatePhrase(id: selectedPhrase.id)
            }

            songActionButton("Delete", systemName: "trash", disabled: phrases.count <= 1) {
                session.removePhrase(id: selectedPhrase.id)
            }

            songActionButton("Open \(selectedPhrase.name)", systemName: "square.split.2x2") {
                onOpenPhrase()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.phraseAccent.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
        )
    }

    private var phraseGrid: some View {
        // Phrases as ROWS, tracks as COLUMNS — the original phrase×track matrix.
        // A track-header row sits on top of the body columns; the leading
        // phrase-label column lines up with the header's leading spacer.
        let activeLayer = matrixLayer
        let accent = activeLayer.map { layerAccent($0.id) } ?? StudioTheme.phraseAccent
        let defaults = inheritedDefaults
        let selectedPhraseID = session.store.selectedPhraseID
        let selectedTrackID = session.store.selectedTrackID

        return ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: gridSpacing) {
                // Header row: leading spacer aligned to the phrase-label column,
                // then one header per track.
                HStack(spacing: gridSpacing) {
                    Color.clear
                        .frame(width: phraseColumnWidth, height: 52)

                    ForEach(tracks, id: \.id) { track in
                        phraseGridTrackHeaderButton(
                            track: track,
                            isSelected: selectedTrackID == track.id,
                            width: trackColumnWidth
                        )
                    }
                }

                // Body: one row per phrase.
                ForEach(phrases, id: \.id) { phrase in
                    let displayedPhrase = session.phraseWithPerformOverlay(phrase)
                    let inherited = defaults.resolved(for: phrase.id)
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
                                onOpenPhrase()
                            },
                            onChangeBarCount: { nextBarCount in
                                session.setPhraseBarCount(nextBarCount, phraseID: phrase.id)
                            },
                            onChangeRepeatCount: { nextRepeatCount in
                                session.setPhraseRepeatCount(nextRepeatCount, phraseID: phrase.id)
                            }
                        )
                        .frame(width: phraseColumnWidth)

                        ForEach(tracks, id: \.id) { track in
                            let trackAccent = StudioTheme.trackAccent(for: track, groups: session.store.trackGroups)
                            Group {
                                if let activeLayer {
                                    PhraseGridCell(
                                        layer: activeLayer,
                                        cell: displayedPhrase.cell(for: activeLayer.id, trackID: track.id),
                                        phrase: displayedPhrase,
                                        track: track,
                                        isSelected: phrase.id == selectedPhraseID && track.id == selectedTrackID,
                                        accent: accent,
                                        trackAccent: trackAccent,
                                        inherited: inherited,
                                        showsTrackName: false
                                    )
                                } else {
                                    PhraseGridEmptyCell()
                                }
                            }
                            .frame(width: trackColumnWidth)
                            .frame(minHeight: PhraseMatrixLayoutPresentation.matrixRowHeight)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                session.setSelectedPhraseID(phrase.id)
                                session.setSelectedTrackID(track.id)
                                onOpenPhrase()
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
        .frame(minHeight: 280)
        .accessibilityIdentifier("song-phrase-grid")
    }

    private func phraseGridTrackHeaderButton(
        track: StepSequenceTrack,
        isSelected: Bool,
        width: CGFloat
    ) -> some View {
        Button {
            session.setSelectedTrackID(track.id)
        } label: {
            PhraseMatrixTrackHeaderCell(
                track: track,
                isSelected: isSelected,
                accent: StudioTheme.trackAccent(for: track, groups: session.store.trackGroups)
            )
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .contentShape(Rectangle())
    }

    private func songActionButton(
        _ title: String,
        systemName: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemName)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .studioText(.labelBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(disabled ? StudioTheme.mutedText.opacity(StudioOpacity.inheritedContent) : StudioTheme.text)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(StudioTheme.subtleFill, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(disabled ? StudioTheme.border.opacity(StudioOpacity.ghostStroke) : StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

private struct SongEmptyPhraseCell: View {
    let slotIndex: Int
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Slot \(slotIndex + 1)")
                        .studioText(.microEmphasis)
                        .tracking(0.7)
                        .foregroundStyle(StudioTheme.mutedText)
                    Spacer(minLength: 0)
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer(minLength: 0)

                Text("Empty")
                    .studioText(.subtitle)
                    .foregroundStyle(StudioTheme.mutedText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(StudioMetrics.Spacing.compact)
            .background(StudioTheme.inset, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                    .stroke(StudioTheme.border.opacity(StudioOpacity.mediumStroke), style: StrokeStyle(lineWidth: StudioMetrics.borderWidth, dash: [5, 5]))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Empty phrase slot \(slotIndex + 1)")
        .accessibilityHint("Add phrase")
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

enum PhraseLayerEditMode: String, CaseIterable, Identifiable {
    case byTrack
    case byValue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .byTrack:
            return "By Track"
        case .byValue:
            return "By Value"
        }
    }

    var symbolName: String {
        switch self {
        case .byTrack:
            return "square.grid.3x3"
        case .byValue:
            return "scope"
        }
    }

    var help: String {
        switch self {
        case .byTrack:
            return "Choose a layer and edit different values per track"
        case .byValue:
            return "Choose a value and apply it to the selected track scope"
        }
    }
}

enum PhraseSceneViewMode: String, CaseIterable, Identifiable {
    case macros
    case slots

    var id: String { rawValue }

    var label: String {
        switch self {
        case .macros:
            return "Macros"
        case .slots:
            return "Slots"
        }
    }

    var symbolName: String {
        switch self {
        case .macros:
            return "dial.max"
        case .slots:
            return "square.grid.2x2"
        }
    }

    var help: String {
        switch self {
        case .macros:
            return "Show slot macro knobs for hands-on tweaking"
        case .slots:
            return "Show every scene so a tap assigns it to the slot"
        }
    }
}

enum PhraseWorkspaceTab: String, CaseIterable, Identifiable {
    case layers
    case values
    case scenes

    var id: String { rawValue }

    var label: String {
        switch self {
        case .layers:
            return "Layer"
        case .values:
            return "Values"
        case .scenes:
            return "Scenes"
        }
    }

    var symbolName: String {
        switch self {
        case .layers:
            return "square.grid.3x3"
        case .values:
            return "scope"
        case .scenes:
            return "square.2.layers.3d"
        }
    }

    var accent: Color {
        switch self {
        case .layers, .values:
            return StudioTheme.phraseAccent
        case .scenes:
            return StudioTheme.phraseAccent
        }
    }

    var help: String {
        switch self {
        case .layers:
            return "Edit phrase layer values by track"
        case .values:
            return "Apply values to the selected track scope"
        case .scenes:
            return "Edit phrase scene values"
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
    // Buttons are the shared 24pt `StudioIconActionButton`.
    var body: some View {
        HStack(spacing: 6) {
            StudioIconActionButton(systemImage: "plus", help: "Insert phrase below", action: onInsertBelow)
            StudioIconActionButton(systemImage: "plus.square.on.square", help: "Duplicate phrase", action: onDuplicate)
            StudioIconActionButton(systemImage: "trash", isDisabled: !canRemove, help: "Remove phrase", action: onRemove)
        }
        .padding(6)
        .background(StudioTheme.subtleFill, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                .stroke(StudioTheme.border, lineWidth: StudioMetrics.borderWidth)
        )
        .frame(maxHeight: .infinity, alignment: .center)
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
        // Colour identifies track identity only: selection may add neutral
        // weight, but it must not change the track border hue.
        .background((isSelected ? StudioTheme.subtleFill : Color.clear), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(accent.opacity(StudioOpacity.mediumStroke), lineWidth: StudioMetrics.borderWidth)
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
                        phraseBadge("Play", accent: StudioTheme.phraseAccent)
                    }
                    if isQueued {
                        phraseBadge("Queue", accent: StudioTheme.phraseAccent)
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

    /// Colour identifies, it never floods (ux-canon rule 12): playing/queued
    /// states live ONLY in the solid Play/Queue badges — never the card
    /// outline. The outline carries selection (surface accent) or the neutral
    /// border; the fill stays on the neutral step. The unlimited repeat is
    /// already stated once by the repeat field ("Unlimited").
    private var rowFill: Color {
        if phrase.loopEnabled || isSelected {
            return StudioTheme.subtleFill
        }
        return Color.clear
    }

    private var rowStroke: Color {
        isSelected ? StudioTheme.phraseAccent : StudioTheme.border
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
                    .background(StudioTheme.subtleFill)

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
                .background(isDisabled ? StudioTheme.disabledSubtleFill : StudioTheme.subtleFill)
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
    let trackAccent: Color
    var inherited: PhraseInheritedDefaults.Resolved?
    var onSelectPatternSlot: ((Int) -> Void)?
    // By Track has no header row, so each cell carries the track name. The Song
    // phrase matrix has its own track-header row, so it passes false to avoid
    // showing the name twice.
    var showsTrackName: Bool = true

    // Inherited cells are a muted variant of explicit ones — no
    // "SINGLE"/"INHERIT" chip repeated in every cell (ux-canon rules 1/3).
    private var isInherited: Bool {
        cell.editMode == .inheritDefault
    }

    private var resolvedValue: PhraseCellValue {
        phrase.resolvedValue(for: layer, trackID: track.id, stepIndex: 0, inherited: inherited)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Track name header inside the cell (By Track has no separate header
            // row), above the value/controls. Suppressed in the Song matrix,
            // which has its own track-header row.
            if showsTrackName {
                Text(track.name)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            cellPreview
            .opacity(isInherited ? StudioOpacity.inheritedContent : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .padding(StudioMetrics.Spacing.compact)
        // Bold-flat pass: no container fill — the value preview is the block,
        // and the container border is always visible so every matrix cell has
        // the same readable boundary.
        .background((isSelected ? StudioTheme.subtleFill : Color.clear), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(
                    trackAccent.opacity(StudioOpacity.mediumStroke),
                    lineWidth: StudioMetrics.borderWidth
                )
        )
        .help(isInherited ? "Follows the layer default. Click to set its own value; Option-click to push a value into this and the following phrases." : "")
    }

    @ViewBuilder
    private var cellPreview: some View {
        if layer.valueType == .patternIndex {
            PatternIndexCellPreview(
                layer: layer,
                resolvedValue: resolvedValue,
                accent: trackAccent,
                summary: valueLabel(resolvedValue, layer: layer),
                isMixed: false,
                metrics: .matrix,
                onSelectSlot: onSelectPatternSlot
            )
        } else {
            PhraseCellPreview(
                layer: layer,
                cell: cell,
                resolvedValue: resolvedValue,
                accent: layer.valueType == .boolean ? trackAccent : accent,
                summary: valueLabel(resolvedValue, layer: layer),
                metrics: .matrix
            )
        }
    }
}

private struct PhraseGridCellTapModifier: ViewModifier {
    let isEnabled: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.gesture(
                TapGesture()
                    .onEnded(onTap)
            )
        } else {
            content
        }
    }
}

private struct PhrasePerformanceToggleCell: View {
    let stateLabel: String
    let detail: String
    let isAvailable: Bool
    let isActive: Bool
    let accent: Color
    let trackAccent: Color

    var body: some View {
        VStack(spacing: 6) {
            Text(stateLabel.uppercased())
                .studioText(.title)
                .foregroundStyle(isActive ? accent : isAvailable ? StudioTheme.text : StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(detail)
                .studioText(.micro)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .center)
        .padding(StudioMetrics.Spacing.compact)
        .background(isActive ? StudioTheme.subtleFill : Color.clear, in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.panel, style: .continuous)
                .stroke(isActive ? accent : trackAccent, lineWidth: isActive ? 2 : StudioMetrics.borderWidth)
        )
        .opacity(isAvailable ? 1 : StudioOpacity.inheritedContent)
        .accessibilityLabel("\(detail), \(stateLabel)")
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
