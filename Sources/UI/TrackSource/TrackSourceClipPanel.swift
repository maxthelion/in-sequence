import SwiftUI

struct TrackSourceClipPanel: View {
    let accent: Color
    let previewClipContent: ClipContent
    let defaultClipNote: ClipStepNote
    let clipMacroSlots: [ClipMacroSlot]
    let macroLanes: [UUID: MacroLane]
    let macroFallbackValues: [UUID: Double]
    let canAssignAUMacros: Bool
    let playingStepIndex: Int?
    let onAssignMacroSlot: (Int) -> Void
    let onUpdateMacroLanes: ([UUID: MacroLane]) -> Void
    let onUpdateClipContent: (ClipContent) -> Void

    var body: some View {
        StudioPanel(
            title: "Clip Contents",
            eyebrow: "Secondary editor for the selected source clip",
            accent: accent,
            showsHeader: true
        ) {
            ClipContentPreview(
                content: previewClipContent,
                defaultNote: defaultClipNote,
                macroSlots: clipMacroSlots,
                macroLanes: macroLanes,
                macroFallbackValues: macroFallbackValues,
                onAssignMacroSlot: canAssignAUMacros ? onAssignMacroSlot : nil,
                onUpdateMacroLanes: onUpdateMacroLanes,
                playingStepIndex: playingStepIndex,
                onChange: onUpdateClipContent
            )
        }
    }
}
