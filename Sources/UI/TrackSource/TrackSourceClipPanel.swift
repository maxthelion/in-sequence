import SwiftUI

struct TrackSourceClipPanel: View {
    let previewClipContent: ClipContent
    let defaultClipNote: ClipStepNote
    /// Surface accent (track identity colour) for the clip editor's
    /// value-selector thumbs.
    let accent: Color
    let clipMacroSlots: [MacroSlot]
    let macroBindings: [TrackMacroBinding]
    let macroLanes: [UUID: MacroLane]
    let macroFallbackValues: [UUID: Double]
    let canAssignAUMacros: Bool
    let playingStepIndex: Int?
    let stepGridCoordinator: StepGridCoordinator?
    let onAssignMacroSlot: (Int) -> Void

    var body: some View {
        ClipContentPreview(
            content: previewClipContent,
            defaultNote: defaultClipNote,
            accent: accent,
            macroSlots: clipMacroSlots,
            macroBindings: macroBindings,
            macroLanes: macroLanes,
            macroFallbackValues: macroFallbackValues,
            stepGridCoordinator: stepGridCoordinator,
            onAssignMacroSlot: canAssignAUMacros ? onAssignMacroSlot : nil,
            playingStepIndex: playingStepIndex
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
