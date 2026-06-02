import SwiftUI

struct TrackSourceClipPanel: View {
    let previewClipContent: ClipContent
    let defaultClipNote: ClipStepNote
    let clipMacroSlots: [MacroSlot]
    let macroBindings: [TrackMacroBinding]
    let macroLanes: [UUID: MacroLane]
    let macroFallbackValues: [UUID: Double]
    let canAssignAUMacros: Bool
    let playingStepIndex: Int?
    let onAssignMacroSlot: (Int) -> Void
    let onUpdateMacroLanes: ([UUID: MacroLane]) -> Void
    let onUpdateClipContent: (ClipContent) -> Void

    var body: some View {
        ClipContentPreview(
            content: previewClipContent,
            defaultNote: defaultClipNote,
            macroSlots: clipMacroSlots,
            macroBindings: macroBindings,
            macroLanes: macroLanes,
            macroFallbackValues: macroFallbackValues,
            onAssignMacroSlot: canAssignAUMacros ? onAssignMacroSlot : nil,
            onUpdateMacroLanes: onUpdateMacroLanes,
            playingStepIndex: playingStepIndex,
            onChange: onUpdateClipContent
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
