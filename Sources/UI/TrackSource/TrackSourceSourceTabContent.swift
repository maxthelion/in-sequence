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
    let clipMacroSlots: [MacroSlot]
    let macroBindings: [TrackMacroBinding]
    let macroLanes: [UUID: MacroLane]
    let macroFallbackValues: [UUID: Double]
    let canAssignAUMacros: Bool
    let playingStepIndex: Int?
    let stepGridCoordinator: StepGridCoordinator?
    let generatedSourceInputClips: [ClipPoolEntry]
    let harmonicSidechainClips: [ClipPoolEntry]
    let onAssignMacroSlot: (Int) -> Void
    let onShowSourcePicker: () -> Void
    let onBackOutSourcePicker: () -> Void
    let onShowSourceGeneratorPool: () -> Void
    let onShowSourceClipPool: () -> Void
    let onCreateBlankGeneratorSource: () -> Void
    let onAssignGeneratorSource: (GeneratorPoolEntry) -> Void
    let onCreateBlankClipSource: () -> Void
    let onAssignClipSource: (ClipPoolEntry) -> Void
    let onRemoveSource: () -> Void
    let onUpdateGeneratorParams: (GeneratorParams) -> Void
    let onSwitchGeneratorKind: (GeneratorPoolEntry, GeneratorKind) -> Void
    let onBakeGeneratorToClip: () -> Void

    private var displayState: TrackSourceSourceDisplayState {
        TrackSourceSourceDisplayState.resolve(
            sourceMode: sourceMode,
            currentClip: currentClip,
            selectedGenerator: selectedGenerator
        )
    }

    // The tab renders inside the editor's `StudioTabWell` (unified tab
    // grammar, Variant D), which owns the outline + content inset; this body
    // is well content only.
    var body: some View {
        switch displayState {
        case .occupiedClip:
            sourceSection

            if sourcePickerStep == nil {
                TrackSourceClipPanel(
                    previewClipContent: previewClipContent,
                    defaultClipNote: defaultClipNote,
                    accent: accent,
                    clipMacroSlots: clipMacroSlots,
                    macroBindings: macroBindings,
                    macroLanes: macroLanes,
                    macroFallbackValues: macroFallbackValues,
                    canAssignAUMacros: canAssignAUMacros,
                    playingStepIndex: playingStepIndex,
                    stepGridCoordinator: stepGridCoordinator,
                    onAssignMacroSlot: onAssignMacroSlot
                )
            }

        case .occupiedGenerator:
            sourceSection

            if sourcePickerStep == nil, let selectedGenerator {
                // WS4 supersedes the WS3 interim GENERATED/READ-ONLY badge:
                // the always-visible RESULT STRIP + Bake dice in the editor
                // header (prototype 14b) now carry the generated-state signal
                // the badge stood in for (the WS3 changelog's documented
                // deferral to WS4's result strip).
                GeneratorParamsEditorView(
                    generator: selectedGenerator,
                    inputClipChoices: generatedSourceInputClips,
                    harmonicSidechainClipChoices: harmonicSidechainClips,
                    sourceMode: .generator,
                    accent: accent,
                    layout: .sourceContained,
                    onUpdate: onUpdateGeneratorParams,
                    onSwitchKind: { onSwitchGeneratorKind(selectedGenerator, $0) },
                    onBakeToClip: onBakeGeneratorToClip
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
                onBack: handlePickerBack,
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
                onRemoveSource: onRemoveSource
            )
        }
    }

    private func handlePickerBack() {
        switch TrackSourceContainedSourcePickerNavigation.destination(from: sourcePickerStep, action: .back) {
        case .root:
            onShowSourcePicker()
        case nil:
            onBackOutSourcePicker()
        case .generatorPool, .clipPool:
            break
        }
    }
}
