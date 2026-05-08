import SwiftUI

struct TrackSourceSourceTabContent: View {
    let sourceMode: TrackSourceMode
    let currentClip: ClipPoolEntry?
    let selectedGenerator: GeneratorPoolEntry?
    let compatibleClips: [ClipPoolEntry]
    let compatibleGenerators: [GeneratorPoolEntry]
    let sourcePickerStep: TrackSourceContainedSourcePickerStep?
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
    let onShowSourcePicker: () -> Void
    let onBackOutSourcePicker: () -> Void
    let onShowSourceGeneratorPool: () -> Void
    let onShowSourceClipPool: () -> Void
    let onCreateBlankGeneratorSource: () -> Void
    let onAssignGeneratorSource: (GeneratorPoolEntry) -> Void
    let onCreateBlankClipSource: () -> Void
    let onAssignClipSource: (ClipPoolEntry) -> Void
    let onPresentClipHistory: () -> Void
    let onRemoveSource: () -> Void
    let onUpdateGeneratorParams: (GeneratorParams) -> Void

    private var displayState: TrackSourceSourceDisplayState {
        TrackSourceSourceDisplayState.resolve(
            sourceMode: sourceMode,
            currentClip: currentClip,
            selectedGenerator: selectedGenerator
        )
    }

    var body: some View {
        switch displayState {
        case .occupiedClip:
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
            sourceSection

        case .occupiedGenerator:
            sourceSection

            if sourcePickerStep == nil, let selectedGenerator {
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

        case .empty:
            sourceSection
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        if let sourcePickerStep {
            TrackSourceContainedSourcePicker(
                step: sourcePickerStep,
                accent: accent,
                compatibleGenerators: compatibleGenerators,
                compatibleClips: compatibleClips,
                onBack: { self.sourcePickerStep == .root ? onBackOutSourcePicker() : onShowSourcePicker() },
                onCancel: onBackOutSourcePicker,
                onShowGeneratorPool: onShowSourceGeneratorPool,
                onShowClipPool: onShowSourceClipPool,
                onCreateBlankGenerator: onCreateBlankGeneratorSource,
                onSelectGenerator: onAssignGeneratorSource,
                onCreateBlankClip: onCreateBlankClipSource,
                onSelectClip: onAssignClipSource
            )
        } else {
            TrackSourceSourceWell(
                sourceMode: sourceMode,
                currentClip: currentClip,
                selectedGenerator: selectedGenerator,
                accent: accent,
                onShowSourcePicker: onShowSourcePicker,
                onPresentClipHistory: onPresentClipHistory,
                onRemoveSource: onRemoveSource
            )
        }
    }
}
