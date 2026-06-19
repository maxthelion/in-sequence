import Foundation

// QA visual-command runner for the kit matrix. Maps the external command
// strings (posted on .drumKitMatrixVisualCommand) onto the same state changes
// and session mutations the UI drives. Split out of DrumKitMatrixView.swift as
// an extension; zero behavior change.

extension DrumKitMatrixView {
    func applyVisualCommand(_ command: String) {
        switch command {
        case "display-16":
            // Legacy 16/32 toggle removed; map to the first bar page so the
            // external QA command runner stays compatible.
            barPage = 0
        case "display-32":
            // Legacy: second bar (17–32) now that the grid is fixed at 16.
            barPage = 1
        case "open-routing":
            isPresentingRoutingEditor = true
        case "close-routing":
            isPresentingRoutingEditor = false
        case "open-template-chooser":
            isPresentingTemplateChooser = true
        case "close-template-chooser":
            isPresentingTemplateChooser = false
        case "open-capture":
            isCaptureOpen = true
        case "close-capture":
            isCaptureOpen = false
        case "history-scrub-back":
            if let model { historyScrubBack(model) }
        case "history-scrub-forward":
            historyScrubForward()
        case "history-live":
            historyJumpToLive()
        case "history-save":
            if let model { saveKitHistoryClipSet(model, slotIndex: historyTargetSlotIndex(model)) }
        case "history-audition-on":
            if let model { startKitAudition(model) }
        case "history-audition-off":
            if let model { stopKitAudition(model) }
        case "history-save-open":
            isPresentingSaveSlotPicker = true
            postRenderedVisualState(isVisible: true)
        case "history-save-close":
            isPresentingSaveSlotPicker = false
            postRenderedVisualState(isVisible: true)
        case "link-on":
            session.setDrumGroupPatternLinked(true, groupID: navigationState.groupID)
        case "link-off":
            session.setDrumGroupPatternLinked(false, groupID: navigationState.groupID)
        case "relink":
            session.reLinkDrumGroupPattern(groupID: navigationState.groupID)
        case "open-kit-fx-chooser":
            isPresentingKitFX = true
        case "close-kit-fx-chooser":
            isPresentingKitFX = false
        case "tab-matrix":
            isCaptureOpen = false
            kitTab = .matrix
        case "tab-fx":
            isCaptureOpen = false
            kitTab = .fx
        case "tab-macros":
            isCaptureOpen = false
            kitTab = .macros
        case "tab-mixer":
            isCaptureOpen = false
            kitTab = .mixer
        case "collapse-row":
            expandedPartID = nil
            postRenderedVisualState(isVisible: true)
        case "row-tab-steps":
            expandedRowTab = .stepsClip
            postRenderedVisualState(isVisible: true)
        case "row-tab-sound":
            expandedRowTab = .sound
            postRenderedVisualState(isVisible: true)
        case "row-tab-fx":
            expandedRowTab = .fx
            postRenderedVisualState(isVisible: true)
        case "row-tab-macros":
            expandedRowTab = .macros
            postRenderedVisualState(isVisible: true)
        case "row-tab-mixer":
            expandedRowTab = .mixer
            postRenderedVisualState(isVisible: true)
        case "source-clip":
            if let model, let memberID = expandedPartID,
               let row = model.rows.first(where: { $0.memberID == memberID }) {
                setMemberSourceMode(row: row, mode: .clip)
            }
        case "source-generator":
            if let model, let memberID = expandedPartID,
               let row = model.rows.first(where: { $0.memberID == memberID }) {
                setMemberSourceMode(row: row, mode: .generator)
            }
        case "back":
            onBack()
        default:
            if command.hasPrefix("expand-part:"),
               let rawIndex = command.split(separator: ":").last,
               let index = Int(rawIndex),
               let model,
               model.rows.indices.contains(index) {
                expandedPartID = model.rows[index].memberID
                expandedRowTab = .stepsClip
                isCaptureOpen = false
                kitTab = .matrix
                postRenderedVisualState(isVisible: true)
            } else if command.hasPrefix("select-index:"),
               let rawIndex = command.split(separator: ":").last,
               let index = Int(rawIndex),
               let model,
               model.rows.indices.contains(index) {
                onSelectPart(model.rows[index].memberID)
            } else if command.hasPrefix("layer:"),
                      let layer = DrumKitMatrixLayer(rawValue: String(command.dropFirst("layer:".count))) {
                selectedLayer = layer
            } else if command.hasPrefix("bar:"),
                      let rawPage = command.split(separator: ":").last,
                      let page = Int(rawPage),
                      page >= 0 {
                barPage = page
            } else if command.hasPrefix("pattern:"),
                      let rawSlot = command.split(separator: ":").last,
                      let slotIndex = Int(rawSlot),
                      (0..<TrackPatternBank.slotCount).contains(slotIndex) {
                session.setDrumGroupSelectedPatternIndex(slotIndex, groupID: navigationState.groupID)
            } else if command.hasPrefix("save-slot:"),
                      let rawSlot = command.split(separator: ":").last,
                      let slotIndex = Int(rawSlot),
                      (0..<TrackPatternBank.slotCount).contains(slotIndex),
                      let model {
                isPresentingSaveSlotPicker = false
                saveKitHistoryClipSet(model, slotIndex: slotIndex)
            } else if command.hasPrefix("history-length:"),
                      let rawSteps = command.split(separator: ":").last,
                      let steps = Int(rawSteps),
                      Self.historyLengthOptions.contains(steps) {
                historyLengthSteps = steps
                historySaveMessage = nil
                refreshKitAuditionIfActive()
                postRenderedVisualState(isVisible: true)
            }
        }
    }
}
