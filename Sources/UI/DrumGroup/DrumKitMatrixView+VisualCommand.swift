import Foundation

// QA visual-command runner for the kit matrix. Maps the external command
// strings (posted on .drumKitMatrixVisualCommand) onto the same state changes
// and session mutations the UI drives. Split out of DrumKitMatrixView.swift as
// an extension.
//
// The external QA visual-scenario runner (VisualScenarioCommandRunner) posts
// raw command STRINGS, so the entry point still accepts a `String`; it is
// parsed into `DrumKitVisualCommand` at the boundary and then handled
// exhaustively. Unknown / retired strings (e.g. the removed 16/32 display
// toggle) parse to `nil` and are ignored, exactly as the old `default` arm did.

/// Typed form of the kit-matrix visual commands. The raw command strings come
/// from the QA visual-scenario runner; `init?(rawValue:)` is the single
/// String → enum boundary so the switch in `applyVisualCommand` is exhaustive.
enum DrumKitVisualCommand: Equatable {
    case openRouting
    case closeRouting
    case openTemplateChooser
    case closeTemplateChooser
    case openCapture
    case closeCapture
    case historyScrubBack
    case historyScrubForward
    case historyLive
    case historySave
    case historyAuditionOn
    case historyAuditionOff
    case historySaveOpen
    case historySaveClose
    case openKitFXChooser
    case closeKitFXChooser
    case tabMatrix
    case tabFX
    case tabMacros
    case tabMixer
    case collapseRow
    case rowTabSteps
    case rowTabSound
    case rowTabFX
    case rowTabMacros
    case rowTabMixer
    case sourceClip
    case sourceGenerator
    case back
    case expandPart(index: Int)
    case selectIndex(index: Int)
    case layer(DrumKitMatrixLayer)
    case bar(page: Int)
    case pattern(slotIndex: Int)
    case saveSlot(slotIndex: Int)
    case historyLength(steps: Int)

    init?(rawValue: String) {
        switch rawValue {
        case "open-routing": self = .openRouting
        case "close-routing": self = .closeRouting
        case "open-template-chooser": self = .openTemplateChooser
        case "close-template-chooser": self = .closeTemplateChooser
        case "open-capture": self = .openCapture
        case "close-capture": self = .closeCapture
        case "history-scrub-back": self = .historyScrubBack
        case "history-scrub-forward": self = .historyScrubForward
        case "history-live": self = .historyLive
        case "history-save": self = .historySave
        case "history-audition-on": self = .historyAuditionOn
        case "history-audition-off": self = .historyAuditionOff
        case "history-save-open": self = .historySaveOpen
        case "history-save-close": self = .historySaveClose
        case "open-kit-fx-chooser": self = .openKitFXChooser
        case "close-kit-fx-chooser": self = .closeKitFXChooser
        case "tab-matrix": self = .tabMatrix
        case "tab-fx": self = .tabFX
        case "tab-macros": self = .tabMacros
        case "tab-mixer": self = .tabMixer
        case "collapse-row": self = .collapseRow
        case "row-tab-steps": self = .rowTabSteps
        case "row-tab-sound": self = .rowTabSound
        case "row-tab-fx": self = .rowTabFX
        case "row-tab-macros": self = .rowTabMacros
        case "row-tab-mixer": self = .rowTabMixer
        case "source-clip": self = .sourceClip
        case "source-generator": self = .sourceGenerator
        case "back": self = .back
        default:
            // Parameterised "<verb>:<value>" commands.
            if let index = Self.intArgument(rawValue, prefix: "expand-part:") {
                self = .expandPart(index: index)
            } else if let index = Self.intArgument(rawValue, prefix: "select-index:") {
                self = .selectIndex(index: index)
            } else if rawValue.hasPrefix("layer:"),
                      let layer = DrumKitMatrixLayer(rawValue: String(rawValue.dropFirst("layer:".count))) {
                self = .layer(layer)
            } else if let page = Self.intArgument(rawValue, prefix: "bar:") {
                self = .bar(page: page)
            } else if let slotIndex = Self.intArgument(rawValue, prefix: "pattern:") {
                self = .pattern(slotIndex: slotIndex)
            } else if let slotIndex = Self.intArgument(rawValue, prefix: "save-slot:") {
                self = .saveSlot(slotIndex: slotIndex)
            } else if let steps = Self.intArgument(rawValue, prefix: "history-length:") {
                self = .historyLength(steps: steps)
            } else {
                return nil
            }
        }
    }

    private static func intArgument(_ rawValue: String, prefix: String) -> Int? {
        guard rawValue.hasPrefix(prefix),
              let rawArgument = rawValue.split(separator: ":").last,
              let value = Int(rawArgument)
        else { return nil }
        return value
    }
}

extension DrumKitMatrixView {
    /// External entry point: the QA runner posts raw command strings. Parse at
    /// the boundary, then dispatch the typed command. Unrecognised strings are
    /// ignored (matches the prior `default` no-op behaviour).
    func applyVisualCommand(_ command: String) {
        guard let parsed = DrumKitVisualCommand(rawValue: command) else { return }
        apply(parsed)
    }

    private func apply(_ command: DrumKitVisualCommand) {
        switch command {
        case .openRouting:
            isPresentingRoutingEditor = true
        case .closeRouting:
            isPresentingRoutingEditor = false
        case .openTemplateChooser:
            isPresentingTemplateChooser = true
        case .closeTemplateChooser:
            isPresentingTemplateChooser = false
        case .openCapture:
            isCaptureOpen = true
        case .closeCapture:
            isCaptureOpen = false
        case .historyScrubBack:
            if let model { historyScrubBack(model) }
        case .historyScrubForward:
            historyScrubForward()
        case .historyLive:
            historyJumpToLive()
        case .historySave:
            if let model { saveKitHistoryClipSet(model, slotIndex: historyTargetSlotIndex(model)) }
        case .historyAuditionOn:
            if let model { startKitAudition(model) }
        case .historyAuditionOff:
            if let model { stopKitAudition(model) }
        case .historySaveOpen:
            isPresentingSaveSlotPicker = true
            postRenderedVisualState(isVisible: true)
        case .historySaveClose:
            isPresentingSaveSlotPicker = false
            postRenderedVisualState(isVisible: true)
        case .openKitFXChooser:
            isPresentingKitFX = true
        case .closeKitFXChooser:
            isPresentingKitFX = false
        case .tabMatrix:
            isCaptureOpen = false
            kitTab = .matrix
        case .tabFX:
            isCaptureOpen = false
            kitTab = .fx
        case .tabMacros:
            isCaptureOpen = false
            kitTab = .macros
        case .tabMixer:
            isCaptureOpen = false
            kitTab = .mixer
        case .collapseRow:
            expandedPartID = nil
            postRenderedVisualState(isVisible: true)
        case .rowTabSteps:
            expandedRowTab = .stepsClip
            postRenderedVisualState(isVisible: true)
        case .rowTabSound:
            expandedRowTab = .sound
            postRenderedVisualState(isVisible: true)
        case .rowTabFX:
            expandedRowTab = .fx
            postRenderedVisualState(isVisible: true)
        case .rowTabMacros:
            expandedRowTab = .macros
            postRenderedVisualState(isVisible: true)
        case .rowTabMixer:
            expandedRowTab = .mixer
            postRenderedVisualState(isVisible: true)
        case .sourceClip:
            if let model, let memberID = expandedPartID,
               let row = model.rows.first(where: { $0.memberID == memberID }) {
                setMemberSourceMode(row: row, mode: .clip)
            }
        case .sourceGenerator:
            if let model, let memberID = expandedPartID,
               let row = model.rows.first(where: { $0.memberID == memberID }) {
                setMemberSourceMode(row: row, mode: .generator)
            }
        case .back:
            onBack()
        case let .expandPart(index):
            if let model, model.rows.indices.contains(index) {
                expandedPartID = model.rows[index].memberID
                expandedRowTab = .stepsClip
                isCaptureOpen = false
                kitTab = .matrix
                postRenderedVisualState(isVisible: true)
            }
        case let .selectIndex(index):
            if let model, model.rows.indices.contains(index) {
                onSelectPart(model.rows[index].memberID)
            }
        case let .layer(layer):
            selectedLayer = layer
        case let .bar(page):
            if page >= 0 { barPage = page }
        case let .pattern(slotIndex):
            if (0..<TrackPatternBank.slotCount).contains(slotIndex) {
                session.setDrumGroupSelectedPatternIndex(slotIndex, groupID: navigationState.groupID)
            }
        case let .saveSlot(slotIndex):
            if (0..<TrackPatternBank.slotCount).contains(slotIndex), let model {
                isPresentingSaveSlotPicker = false
                saveKitHistoryClipSet(model, slotIndex: slotIndex)
            }
        case let .historyLength(steps):
            if Self.historyLengthOptions.contains(steps) {
                historyLengthSteps = steps
                historySaveMessage = nil
                refreshKitAuditionIfActive()
                postRenderedVisualState(isVisible: true)
            }
        }
    }
}
