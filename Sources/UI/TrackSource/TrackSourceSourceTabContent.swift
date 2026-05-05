import SwiftUI

struct TrackSourceSourceTabContent: View {
    let sourceMode: TrackSourceMode
    let currentClip: ClipPoolEntry?
    let selectedGenerator: GeneratorPoolEntry?
    let compatibleGenerators: [GeneratorPoolEntry]
    let accent: Color
    let previewClipContent: ClipContent
    let defaultClipNote: ClipStepNote
    let clipMacroSlots: [ClipMacroSlot]
    let macroLanes: [UUID: MacroLane]
    let macroFallbackValues: [UUID: Double]
    let canAssignAUMacros: Bool
    let playingStepIndex: Int?
    let generatedSourceInputClips: [ClipPoolEntry]
    let harmonicSidechainClips: [ClipPoolEntry]
    let onAssignMacroSlot: (Int) -> Void
    let onUpdateMacroLanes: ([UUID: MacroLane]) -> Void
    let onUpdateClipContent: (ClipContent) -> Void
    let onShowGeneratorPicker: () -> Void
    let onPresentClipHistory: () -> Void
    let onRemoveGeneratorSource: () -> Void
    let onUpdateGeneratorParams: (GeneratorParams) -> Void

    var body: some View {
        switch sourceMode {
        case .clip:
            TrackSourceClipPanel(
                accent: StudioTheme.violet,
                previewClipContent: previewClipContent,
                defaultClipNote: defaultClipNote,
                clipMacroSlots: clipMacroSlots,
                macroLanes: macroLanes,
                macroFallbackValues: macroFallbackValues,
                canAssignAUMacros: canAssignAUMacros,
                playingStepIndex: playingStepIndex,
                onAssignMacroSlot: onAssignMacroSlot,
                onUpdateMacroLanes: onUpdateMacroLanes,
                onUpdateClipContent: onUpdateClipContent
            )
            sourceWell

        case .generator:
            sourceWell

            if let selectedGenerator {
                GeneratorParamsEditorView(
                    generator: selectedGenerator,
                    inputClipChoices: generatedSourceInputClips,
                    harmonicSidechainClipChoices: harmonicSidechainClips,
                    sourceMode: .generator,
                    accent: accent,
                    layout: .sourceOnly,
                    onUpdate: onUpdateGeneratorParams
                )
            }
        }
    }

    private var sourceWell: some View {
        TrackSourceSourceWell(
            sourceMode: sourceMode,
            currentClip: currentClip,
            selectedGenerator: selectedGenerator,
            compatibleGenerators: compatibleGenerators,
            accent: accent,
            onShowGeneratorPicker: onShowGeneratorPicker,
            onPresentClipHistory: onPresentClipHistory,
            onRemoveGeneratorSource: onRemoveGeneratorSource
        )
    }
}
