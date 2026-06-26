import SwiftUI

/// Matrix-wide step layer. The same layer set the single-track step editor
/// offers for note-grid clips (`ClipEditorMode`): on/off triggers, velocity,
/// and chance. Macro lanes are per-track bindings and stay single-track only.
/// Kit-altitude tab bar (track-view IA, AC13/AC23). The tabs operate at
/// KIT-BUS scope, distinct from the per-part FX/Macros/Mixer reached by
/// diving into a single part. Capture + Perform are header buttons, NOT tabs.
enum DrumKitTab: String, CaseIterable, Identifiable {
    case matrix
    case fx
    case macros
    case mixer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .matrix:
            return "Matrix"
        case .fx:
            return "FX"
        case .macros:
            return "Macros"
        case .mixer:
            return "Mixer"
        }
    }
}

/// Mini-tabs inside an EXPANDED part row (AC21). Mirrors the single-track
/// detail tab order (Steps/Clip · Sound · FX · Macros · Mixer) but renders
/// inline, scoped to the row's member track id — the user never leaves the
/// kit matrix.
enum DrumKitRowTab: String, CaseIterable, Identifiable {
    case stepsClip
    case sound
    case fx
    case macros
    case mixer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stepsClip:
            return "Steps/Clip"
        case .sound:
            return "Sound"
        case .fx:
            return "FX"
        case .macros:
            return "Macros"
        case .mixer:
            return "Mixer"
        }
    }
}

/// Identifiable wrapper so a member track id can drive `.sheet(item:)` for the
/// expanded row's "+ FX" picker (UUID is not Identifiable on its own).
struct ExpandedFXTarget: Identifiable {
    let memberID: UUID
    var id: UUID { memberID }
}

/// Identifiable wrapper driving `.sheet(item:)` for the expanded row's macro
/// "assign slot" picker (Macros mini-tab). Carries both the member whose macro
/// slot is being assigned and the slot index, so the AU-parameter picker can be
/// presented in-place without leaving the kit view.
struct ExpandedMacroTarget: Identifiable {
    let memberID: UUID
    let slotIndex: Int
    var id: String { "\(memberID.uuidString)-\(slotIndex)" }
}

/// Identifiable wrapper driving `.sheet(item:)` for the expanded row's "Load AU…"
/// instrument chooser (Sound mini-tab). Carries the member whose sound source is
/// being swapped from the sampler to an AU instrument.
struct ExpandedSoundAUTarget: Identifiable {
    let memberID: UUID
    var id: UUID { memberID }
}

/// Identifiable wrapper driving `.sheet(item:)` for the expanded row's AU
/// preset browser (Sound mini-tab). Carries the member whose AU sound source's
/// presets are being browsed.
struct ExpandedSoundPresetTarget: Identifiable {
    let memberID: UUID
    var id: UUID { memberID }
}

enum DrumKitMatrixLayer: String, CaseIterable, Identifiable {
    case steps
    case velocity
    case chance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps:
            return "Steps"
        case .velocity:
            return "Velocity"
        case .chance:
            return "Chance"
        }
    }
}

/// Pure cell-edit transforms for the kit matrix. Delegates to
/// `ClipNoteGridStepEditing` — the same implementation the single-track clip
/// editor commits through — so a matrix edit is the identical mutation.
enum DrumKitMatrixStepEdit {
    static func tappedContent(
        layer: DrumKitMatrixLayer,
        stepIndex: Int,
        lengthSteps: Int,
        steps: [ClipStep],
        defaultNote: ClipStepNote
    ) -> ClipContent? {
        guard steps.indices.contains(stepIndex) else { return nil }
        switch layer {
        case .steps:
            return ClipNoteGridStepEditing.togglingStep(
                at: stepIndex,
                lengthSteps: lengthSteps,
                steps: steps,
                lane: .main,
                defaultNote: defaultNote
            )
        case .velocity:
            let nextValue = ClipNoteGridStepEditing.cycledValue(
                after: ClipNoteGridStepEditing.velocityValue(for: steps[stepIndex], lane: .main),
                allowedValues: ClipNoteGridStepEditing.velocityCycleValues
            )
            return ClipNoteGridStepEditing.updatingLaneVelocities(
                lane: .main,
                values: [nextValue],
                visibleIndices: [stepIndex],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )
        case .chance:
            let nextValue = ClipNoteGridStepEditing.cycledValue(
                after: ClipNoteGridStepEditing.chanceValue(for: steps[stepIndex], lane: .main),
                allowedValues: ClipNoteGridStepEditing.chanceCycleValues
            )
            return ClipNoteGridStepEditing.updatingLaneChances(
                lane: .main,
                values: [nextValue],
                visibleIndices: [stepIndex],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )
        }
    }

    static func draggedContent(
        layer: DrumKitMatrixLayer,
        stepIndex: Int,
        fraction: Double,
        lengthSteps: Int,
        steps: [ClipStep],
        defaultNote: ClipStepNote
    ) -> ClipContent? {
        guard steps.indices.contains(stepIndex) else { return nil }
        switch layer {
        case .steps:
            return nil
        case .velocity:
            return ClipNoteGridStepEditing.updatingLaneVelocities(
                lane: .main,
                values: [fraction * 127.0],
                visibleIndices: [stepIndex],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )
        case .chance:
            return ClipNoteGridStepEditing.updatingLaneChances(
                lane: .main,
                values: [fraction],
                visibleIndices: [stepIndex],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )
        }
    }
}

struct DrumKitMatrixView: View {
    @Binding var document: SeqAIDocument
    @Environment(SequencerDocumentSession.self) var session
    @Environment(EngineController.self) var engineController

    let navigationState: DrumKitWorkspaceNavigationState
    /// When the matrix is the track editor's home (kit-first), there is no
    /// "back" target above it, so the back affordance is hidden. Defaults to
    /// `true` so any other caller keeps the original behaviour.
    var showsBackButton = true
    let onBack: () -> Void
    let onSelectPart: (UUID) -> Void

    /// Fixed 16-step grid; paging across bars replaces the old 16/32 toggle.
    static let stepsPerBar = 16
    /// Which 16-step bar window is visible for every row in lockstep.
    @State var barPage = 0
    @State var selectedLayer: DrumKitMatrixLayer = .steps
    @State var isPresentingRoutingEditor = false
    @State var isPresentingTemplateChooser = false
    /// Which kit-bus tab is shown (Matrix · FX · Macros · Mixer). Ignored while
    /// `isCaptureOpen` is true — Capture replaces the tab body (AC14 header).
    @State var kitTab: DrumKitTab = .matrix
    /// Capture surface replaces the tab content; the Patterns row stays visible
    /// above it so a captured set can be assigned to a slot (AC12/AC14).
    @State var isCaptureOpen = false
    /// "+ FX" picker for the kit bus (AC23 kit FX).
    @State var isPresentingKitFX = false
    /// Shared history selection length (AC15/AC16), in steps. ½/1/2/4 bars =
    /// 8/16/32/64. Applies to EVERY member's window in lockstep.
    @State var historyLengthSteps = 16
    /// Shared scrubber position (AC16): how many bars BACK from the live edge
    /// the selection window sits. 0 == live (newest). Moves every member's
    /// window in lockstep.
    @State var historyBarsBack = 0
    /// Last save feedback shown in the history footer.
    @State var historySaveMessage: String?
    /// AC15 audition: when true, every member's audition override is set to its
    /// windowed pseudo-clip so the whole kit plays the selected window as its
    /// clips. Cleared on toggle-off, capture close, and after a save.
    @State var isAuditioningCapture = false
    /// Whether the save-slot picker (P1–P16) popover is shown (AC15 save).
    @State var isPresentingSaveSlotPicker = false
    /// AC21 accordion: which part row is expanded inline (nil == all compact).
    /// Transient UI state; expanding does not change link/pattern state.
    @State var expandedPartID: UUID?
    /// Selected mini-tab inside the expanded row's inline detail panel.
    @State var expandedRowTab: DrumKitRowTab = .stepsClip
    /// "+ FX" picker target for the expanded part's per-track FX chain (AC21
    /// FX mini-tab). nil when closed. Wrapped so it can drive `.sheet(item:)`.
    @State var expandedFXTarget: ExpandedFXTarget?
    /// Macro "assign slot" picker target for the expanded part's Macros
    /// mini-tab. nil when closed. Drives the AU-parameter picker sheet so a
    /// macro slot can be assigned/changed without leaving the kit view.
    @State var expandedMacroTarget: ExpandedMacroTarget?
    /// "Load AU…" instrument picker target for the expanded part's Sound
    /// mini-tab (AU sound source). nil when closed. Drives the AU-instrument
    /// chooser sheet so a part's sampler can be swapped for an AU instrument.
    @State var expandedSoundAUTarget: ExpandedSoundAUTarget?
    /// Preset-browser target for the expanded part's AU sound source. nil when
    /// closed. Drives `PresetBrowserSheet` bound to the member's AU host.
    @State var expandedSoundPresetTarget: ExpandedSoundPresetTarget?

    var model: DrumKitMatrixModel? {
        DrumKitMatrixModel(
            groupID: navigationState.groupID,
            originatingPartID: navigationState.originatingPartID,
            displayStepCount: Self.stepsPerBar,
            tracks: session.store.tracks,
            trackGroups: session.store.trackGroups,
            layers: session.store.layers,
            selectedPhrase: session.store.selectedPhrase,
            patternBanks: Array(session.store.patternBanksByTrackID.values),
            clipPool: session.store.clipPool,
            generatorPool: session.store.generatorPool
        )
    }

    /// The kit accent, derived straight from the group's stored color hex.
    /// This intentionally does NOT build `DrumKitMatrixModel` — `colorHex` is a
    /// verbatim copy of `group.color`, and `accent` is read ~37× per render, so
    /// rebuilding the whole model (tracksByID dict + every member's note-grid
    /// decode + occupiedSlotIndexes) just to read the color was pure waste.
    /// When the group no longer resolves, `model` is also nil, so falling back
    /// to `StudioTheme.success` matches the old `Color(hex: "") ?? success`.
    var accent: Color {
        let hex = session.store.trackGroups
            .first(where: { $0.id == navigationState.groupID })?
            .color
        return Color(hex: hex ?? "") ?? StudioTheme.success
    }

    /// The kit's own bus, resolved from its members' `outputBusID` (kits route
    /// to a dedicated bus by default). The first member with a resolvable bus
    /// wins; nil means the kit is on Master / unrouted, in which case the FX
    /// and Mixer tabs show an explanatory empty state. (AC23 kit-bus scope.)
    func kitBus(_ model: DrumKitMatrixModel) -> MixerBus? {
        let buses = session.store.buses
        let tracksByID = Dictionary(
            uniqueKeysWithValues: session.store.tracks.map { ($0.id, $0) }
        )
        for row in model.rows {
            guard let busID = tracksByID[row.memberID]?.outputBusID,
                  let bus = buses.first(where: { $0.id == busID })
            else { continue }
            return bus
        }
        return nil
    }

    /// Longest editable/read-only row length, in steps, across the kit. Drives
    /// how many 16-step bar pages the pager offers.
    func longestRowLength(_ model: DrumKitMatrixModel) -> Int {
        var maxLength = Self.stepsPerBar
        for row in model.rows {
            switch row.content {
            case let .editable(_, lengthSteps, steps):
                maxLength = max(maxLength, max(lengthSteps, steps.count))
            case let .readOnly(_, _, steps):
                maxLength = max(maxLength, steps.count)
            case .generator:
                break
            }
        }
        return maxLength
    }

    /// Number of 16-step bar pages, at least one. Delegates the page math to
    /// the testable `DrumKitBarPaging` value type.
    func barPageCount(_ model: DrumKitMatrixModel) -> Int {
        barPageCount(longestRowLength: longestRowLength(model))
    }

    /// Page count from a pre-computed longest-row length. Lets a caller compute
    /// `longestRowLength` once per render and reuse it for both paging helpers
    /// instead of re-scanning every row 3–4× per render.
    func barPageCount(longestRowLength: Int) -> Int {
        DrumKitBarPaging.pageCount(
            length: longestRowLength,
            stepsPerBar: Self.stepsPerBar
        )
    }

    /// `barPage` clamped to the valid range for the current model. Delegates the
    /// clamp to the testable `DrumKitBarPaging` value type.
    func clampedPage(_ model: DrumKitMatrixModel) -> Int {
        clampedPage(longestRowLength: longestRowLength(model))
    }

    /// Clamped page from a pre-computed longest-row length (see `barPageCount`).
    func clampedPage(longestRowLength: Int) -> Int {
        DrumKitBarPaging.clampedPage(
            barPage,
            length: longestRowLength,
            stepsPerBar: Self.stepsPerBar
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            if let model {
                kitBody(model)
            } else {
                unavailableState
            }
        }
        .padding(StudioMetrics.Spacing.section)
        .sheet(isPresented: $isPresentingRoutingEditor) {
            if let draft = DrumGroupRoutingEditorDraft(
                groupID: navigationState.groupID,
                trackGroups: session.store.trackGroups,
                tracks: session.store.tracks
            ) {
                DrumGroupRoutingEditorSheet(
                    draft: draft,
                    audioInstrumentChoices: engineController.availableAudioInstruments,
                    onApply: { routingDraft in
                        session.applyDrumGroupRoutingDraft(routingDraft)
                        isPresentingRoutingEditor = false
                    },
                    onCancel: {
                        isPresentingRoutingEditor = false
                    }
                )
            } else {
                Text("Routing editor unavailable")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .padding(StudioMetrics.Spacing.page)
                    .background(StudioTheme.stageFill)
            }
        }
        .sheet(isPresented: $isPresentingTemplateChooser) {
            if let model,
               let group = session.store.trackGroups.first(where: { $0.id == model.groupID }) {
                DrumKitTemplateChooserSheet(
                    groupName: model.groupName,
                    targetSlotIndex: model.groupSelectedSlotIndex ?? model.rows.first?.patternSlotIndex ?? 0,
                    previewProvider: { template, slotIndex in
                        PatternTemplateApplicationPreview(
                            template: template,
                            group: group,
                            tracks: session.store.tracks,
                            patternBanks: Array(session.store.patternBanksByTrackID.values),
                            clipPool: session.store.clipPool,
                            slotIndex: slotIndex
                        )
                    },
                    onApply: { template, slotIndex in
                        session.applyPatternTemplate(template, toGroup: group.id, slotIndex: slotIndex)
                        isPresentingTemplateChooser = false
                    },
                    onCancel: {
                        isPresentingTemplateChooser = false
                    }
                )
            } else {
                Text("Template chooser unavailable")
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.mutedText)
                    .padding(StudioMetrics.Spacing.page)
                    .background(StudioTheme.stageFill)
            }
        }
        .sheet(isPresented: $isPresentingKitFX) {
            kitFXChooserSheet
        }
        .onAppear {
            // Drain QA commands that were posted before this view mounted (the
            // open-kit-view / dive-in race): e.g. open-routing for the routing
            // editor, or expand-part:N,row-tab-sound for the expanded row.
            // Replaying them on mount makes those captures deterministic.
            for command in VisualScenarioCommandRunner.drainPendingDrumKitMatrixCommands() {
                applyVisualCommand(command)
            }
            postRenderedVisualState(isVisible: true)
        }
        .onDisappear {
            stopKitAudition()
            postRenderedVisualState(isVisible: false)
        }
        .onChange(of: barPage) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: selectedLayer) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: kitTab) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: isCaptureOpen) {
            if !isCaptureOpen {
                stopKitAudition()
                isPresentingSaveSlotPicker = false
            }
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: isPresentingRoutingEditor) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: isPresentingTemplateChooser) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: session.revision) {
            postRenderedVisualState(isVisible: true)
        }
        .onChange(of: navigationState) {
            postRenderedVisualState(isVisible: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .drumKitMatrixVisualCommand)) { notification in
            guard let command = notification.object as? String else { return }
            applyVisualCommand(command)
        }
    }

    func postRenderedVisualState(isVisible: Bool) {
        // Build the model once for this status snapshot (this runs on lifecycle/
        // change callbacks, not the render path, but there is no reason to
        // rebuild it for every field below).
        let model = self.model
        let longest = model.map(longestRowLength)
        let groupSlot = model?.groupSelectedSlotIndex
        let expandedIndex: Int? = {
            guard let model, let expandedPartID else { return nil }
            return model.rows.firstIndex { $0.memberID == expandedPartID }
        }()
        let expandedSourceMode: String = {
            guard isVisible, let model, let expandedPartID,
                  let row = model.rows.first(where: { $0.memberID == expandedPartID })
            else { return "none" }
            return row.sourceMode.rawValue
        }()
        let state = DrumKitRenderedVisualState(
            visible: isVisible,
            routingEditorVisible: isVisible && isPresentingRoutingEditor,
            templateChooserVisible: isVisible && isPresentingTemplateChooser,
            displayStepCount: Self.stepsPerBar,
            barPage: isVisible ? (longest.map(clampedPage(longestRowLength:)) ?? 0) : 0,
            barPageCount: isVisible ? (longest.map(barPageCount(longestRowLength:)) ?? 1) : 1,
            layer: isVisible ? selectedLayer.rawValue : "none",
            groupPatternSlot: isVisible ? (groupSlot.map { "\($0 + 1)" } ?? "mixed") : "none",
            // Patterns are global across the kit: members always share one slot
            // and can never diverge through the UI, so the kit is always
            // "linked" and the link can never be "broken". The wire keys stay
            // for QA-harness stability.
            patternLinked: isVisible,
            patternLinkBroken: false,
            groupName: isVisible ? model?.groupName ?? "none" : "none",
            memberCount: isVisible ? model?.rows.count ?? 0 : 0,
            kitTab: isVisible ? (isCaptureOpen ? "capture" : kitTab.rawValue) : "none",
            captureOpen: isVisible && isCaptureOpen,
            kitFXChooserVisible: isVisible && isPresentingKitFX,
            historyLengthSteps: isVisible && isCaptureOpen ? historyLengthSteps : 0,
            historyBarsBack: isVisible && isCaptureOpen ? historyBarsBack : 0,
            historyWindow: isVisible && isCaptureOpen
                ? (historyBarsBack == 0 ? "live" : "\(historyBarsBack) back")
                : "none",
            historyAuditioning: isVisible && isCaptureOpen && isAuditioningCapture,
            historySaveSlotPickerVisible: isVisible && isCaptureOpen && isPresentingSaveSlotPicker,
            expandedPartIndex: isVisible ? expandedIndex : nil,
            expandedRowTab: isVisible && expandedIndex != nil ? expandedRowTab.rawValue : "none",
            expandedSourceMode: expandedSourceMode
        )
        NotificationCenter.default.post(
            name: .drumKitMatrixRenderedVisualState,
            object: nil,
            userInfo: state.notificationUserInfo
        )
    }

    /// Kit page layout (AC12/AC13/AC14): persistent Patterns row, then either
    /// the Capture history surface (replaces the tabs) or the kit tab bar +
    /// selected tab body. The Patterns row is ALWAYS above and stays visible
    /// across every tab and during Capture.
    @ViewBuilder
    func kitBody(_ model: DrumKitMatrixModel) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if isCaptureOpen {
                captureHistoryBody(model)
            } else {
                kitTabBar
                selectedKitTabBody(model)
            }
        }
    }

    /// Matrix · FX · Macros · Mixer (AC13). Hidden while Capture is open.
    /// Styled to match the normal-track segmented tab bar
    /// (`TrackSourceSlotWellTabBar`): each tab is a neutral-filled pill with an
    /// uppercase eyebrow label and an accent underline + ghost-stroke when
    /// selected, so the kit surface reads with the same grammar as a track.
    var kitTabBar: some View {
        HStack(spacing: 4) {
            ForEach(DrumKitTab.allCases) { tab in
                kitTabButton(tab)
            }
        }
    }

    func kitTabButton(_ tab: DrumKitTab) -> some View {
        let isSelected = kitTab == tab
        // Underline-tab grammar shared with TrackSourceSlotWellTabBar; the kit
        // tabs are label-only (no per-tab state badge).
        return StudioSlotTabButton(
            title: tab.title,
            isSelected: isSelected,
            selectedAccent: accent,
            action: { kitTab = tab }
        )
        .accessibilityIdentifier("kit-tab-\(tab.rawValue)")
        .accessibilityLabel("Kit tab \(tab.title)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    @ViewBuilder
    func selectedKitTabBody(_ model: DrumKitMatrixModel) -> some View {
        switch kitTab {
        case .matrix:
            matrixTabBody(model)
        case .fx:
            kitFXTabBody(model)
        case .macros:
            kitMacrosTabBody(model)
        case .mixer:
            kitMixerTabBody(model)
        }
    }

    /// Matrix tab: the existing matrix content, minus the group pattern row
    /// (which now lives in the persistent Patterns row above). (AC23)
    @ViewBuilder
    func matrixTabBody(_ model: DrumKitMatrixModel) -> some View {
        StudioPanel(title: "Kit Matrix", accent: accent, showsHeader: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    layerSelector

                    fillModeControl(model)

                    barPager(model)

                    Spacer(minLength: 0)

                    headerActionButton(title: "Apply Template…", systemImage: "square.grid.2x2") {
                        isPresentingTemplateChooser = true
                    }
                    .help("Apply a pattern template into the selected group pattern slot")
                }

                if model.staleMemberCount > 0 {
                    staleMemberBanner(count: model.staleMemberCount)
                }

                if model.rows.isEmpty {
                    emptyRowsState
                } else {
                    matrixRows(model)
                }
            }
        }
    }

    /// Commit a cell tap for a row through `ensureClipAndMutate`, with the
    /// same shared content transform (`ClipNoteGridStepEditing`). The matrix
    /// keeps the slot-address key because a tap on an empty slot must
    /// materialize a clip; the single-track editor (which only ever edits an
    /// existing clip) commits through `StepGridCoordinator.commitEdit`.
    func commitTap(row: DrumKitMatrixModel.Row, stepIndex: Int) {
        guard case let .editable(_, lengthSteps, steps) = row.content,
              let updated = DrumKitMatrixStepEdit.tappedContent(
                  layer: selectedLayer,
                  stepIndex: stepIndex,
                  lengthSteps: lengthSteps,
                  steps: steps,
                  defaultNote: row.defaultNote
              )
        else { return }

        session.ensureClipAndMutate(
            at: PatternSlotAddress(trackID: row.memberID, slotIndex: row.patternSlotIndex)
        ) { _, entry in
            entry.content = updated
        }
    }

    func commitDrag(row: DrumKitMatrixModel.Row, stepIndex: Int, fraction: Double) {
        guard case let .editable(_, lengthSteps, steps) = row.content,
              let updated = DrumKitMatrixStepEdit.draggedContent(
                  layer: selectedLayer,
                  stepIndex: stepIndex,
                  fraction: fraction,
                  lengthSteps: lengthSteps,
                  steps: steps,
                  defaultNote: row.defaultNote
              )
        else { return }

        session.ensureClipAndMutate(
            at: PatternSlotAddress(trackID: row.memberID, slotIndex: row.patternSlotIndex)
        ) { _, entry in
            entry.content = updated
        }
    }

    var unavailableState: some View {
        StudioPanel(title: "Kit Matrix", eyebrow: "Group unavailable", accent: StudioTheme.amber) {
            Text("The selected kit no longer resolves.")
                .studioText(.body)
                .foregroundStyle(StudioTheme.mutedText)
        }
    }
}

private extension Color {
    init?(hex: String) {
        var string = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        string = string.replacingOccurrences(of: "#", with: "")
        guard string.count == 6, let value = UInt64(string, radix: 16) else {
            return nil
        }

        self.init(
            red: Double((value & 0xFF0000) >> 16) / 255.0,
            green: Double((value & 0x00FF00) >> 8) / 255.0,
            blue: Double(value & 0x0000FF) / 255.0
        )
    }
}

// MARK: - Rendered visual state (typed producer contract)

/// Typed producer-side contract for the drum-kit matrix rendered-visual-state
/// notification. The view builds this struct; `notificationUserInfo` serializes
/// it into the string-keyed `userInfo` that `VisualScenarioCommandRunner` and
/// `scripts/visual-scenarios/drum-kit-matrix.sh` read. The wire keys/values are
/// byte-for-byte identical to the old inline dictionary — `expandedPartIndex`
/// is still encoded as `Int` with `-1` standing in for `nil` (the `-1` sentinel
/// exists ONLY at this wire boundary, never in the Swift type).
struct DrumKitRenderedVisualState: Equatable, Sendable {
    var visible: Bool
    var routingEditorVisible: Bool
    var templateChooserVisible: Bool
    var displayStepCount: Int
    var barPage: Int
    var barPageCount: Int
    var layer: String
    var groupPatternSlot: String
    var patternLinked: Bool
    var patternLinkBroken: Bool
    var groupName: String
    var memberCount: Int
    var kitTab: String
    var captureOpen: Bool
    var kitFXChooserVisible: Bool
    var historyLengthSteps: Int
    var historyBarsBack: Int
    var historyWindow: String
    var historyAuditioning: Bool
    var historySaveSlotPickerVisible: Bool
    /// `nil` means "no expanded part". On the wire this encodes as `-1`.
    var expandedPartIndex: Int?
    var expandedRowTab: String
    var expandedSourceMode: String

    /// `true` when a part row is expanded — derived from `expandedPartIndex`.
    var rowExpanded: Bool {
        expandedPartIndex != nil
    }

    /// Serialize into the exact string-keyed `userInfo` the QA/observability
    /// path expects. Keys/values must stay byte-for-byte stable.
    var notificationUserInfo: [String: Any] {
        [
            "visible": visible,
            "routingEditorVisible": routingEditorVisible,
            "templateChooserVisible": templateChooserVisible,
            "displayStepCount": displayStepCount,
            "barPage": barPage,
            "barPageCount": barPageCount,
            "layer": layer,
            "groupPatternSlot": groupPatternSlot,
            "patternLinked": patternLinked,
            "patternLinkBroken": patternLinkBroken,
            "groupName": groupName,
            "memberCount": memberCount,
            "kitTab": kitTab,
            "captureOpen": captureOpen,
            "kitFXChooserVisible": kitFXChooserVisible,
            "historyLengthSteps": historyLengthSteps,
            "historyBarsBack": historyBarsBack,
            "historyWindow": historyWindow,
            "historyAuditioning": historyAuditioning,
            "historySaveSlotPickerVisible": historySaveSlotPickerVisible,
            "rowExpanded": rowExpanded,
            "expandedPartIndex": expandedPartIndex ?? -1,
            "expandedRowTab": expandedRowTab,
            "expandedSourceMode": expandedSourceMode,
        ]
    }
}
