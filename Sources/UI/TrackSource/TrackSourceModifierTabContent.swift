import SwiftUI

struct TrackSourceModifierTabContent: View {
    let selectedGenerator: GeneratorPoolEntry?
    let isBypassed: Bool
    let compatibleGenerators: [GeneratorPoolEntry]
    let sourceMode: TrackSourceMode
    let generatedSourceInputClips: [ClipPoolEntry]
    let harmonicSidechainClips: [ClipPoolEntry]
    let onShowGeneratorPicker: () -> Void
    let onToggleBypassed: () -> Void
    let onRemoveModifier: () -> Void
    let onUpdateGeneratorParams: (GeneratorParams) -> Void

    var body: some View {
        modifierWell

        if let selectedGenerator {
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

    private var modifierWell: some View {
        TrackSourceModifierWell(
            selectedGenerator: selectedGenerator,
            isBypassed: isBypassed,
            compatibleGenerators: compatibleGenerators,
            onShowGeneratorPicker: onShowGeneratorPicker,
            onToggleBypassed: onToggleBypassed,
            onRemoveModifier: onRemoveModifier
        )
    }
}
