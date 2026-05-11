import SwiftUI

struct TrackSourceModifierTabContent: View {
    let trackType: TrackType
    let selectedGenerator: GeneratorPoolEntry?
    let isBypassed: Bool
    let compatibleGenerators: [GeneratorPoolEntry]
    let modifierPickerStep: TrackSourceContainedModifierPickerStep?
    let sourceMode: TrackSourceMode
    let generatedSourceInputClips: [ClipPoolEntry]
    let harmonicSidechainClips: [ClipPoolEntry]
    let onShowGeneratorPicker: () -> Void
    let onBackOutGeneratorPicker: () -> Void
    let onShowModifierPool: () -> Void
    let onCreateBlankModifier: () -> Void
    let onSelectModifier: (GeneratorPoolEntry) -> Void
    let onToggleBypassed: () -> Void
    let onRemoveModifier: () -> Void
    let onUpdateGeneratorParams: (GeneratorParams) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            modifierWell

            if let modifierPickerStep {
                TrackSourceContainedModifierPicker(
                    step: modifierPickerStep,
                    compatibleModifiers: compatibleGenerators,
                    onBack: onShowGeneratorPicker,
                    onCancel: onBackOutGeneratorPicker,
                    onShowModifierPool: onShowModifierPool,
                    onCreateBlankModifier: onCreateBlankModifier,
                    onSelectModifier: onSelectModifier
                )
            }

            if modifierPickerStep == nil, let selectedGenerator {
                GeneratorParamsEditorView(
                    generator: selectedGenerator,
                    inputClipChoices: generatedSourceInputClips,
                    harmonicSidechainClipChoices: harmonicSidechainClips,
                    sourceMode: sourceMode,
                    accent: StudioTheme.violet,
                    layout: .modifierOnly,
                    onUpdate: onUpdateGeneratorParams
                )
            }
        }
    }

    private var modifierWell: some View {
        TrackSourceModifierWell(
            trackType: trackType,
            selectedGenerator: selectedGenerator,
            isBypassed: isBypassed,
            onShowGeneratorPicker: onShowGeneratorPicker,
            onToggleBypassed: onToggleBypassed,
            onRemoveModifier: onRemoveModifier
        )
    }
}
