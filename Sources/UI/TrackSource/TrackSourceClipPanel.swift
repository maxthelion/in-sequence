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
    let canRandomizeClip: Bool
    let isRandomizePanelVisible: Bool
    let hasSavedRandomizeSettings: Bool
    let randomizePanel: () -> AnyView
    let onRandomizeClip: () -> Void
    let onToggleRandomizePanel: () -> Void

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
            canRandomize: canRandomizeClip,
            isRandomizePanelVisible: isRandomizePanelVisible,
            hasSavedRandomizeSettings: hasSavedRandomizeSettings,
            randomizePanel: randomizePanel,
            onRandomize: onRandomizeClip,
            onToggleRandomizePanel: onToggleRandomizePanel,
            playingStepIndex: playingStepIndex
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
