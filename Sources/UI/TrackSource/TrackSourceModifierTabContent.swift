import SwiftUI

struct TrackSourceModifierTabContent: View {
    let trackType: TrackType
    let selectedGenerator: GeneratorPoolEntry?
    let isBypassed: Bool
    /// The ONE chrome accent of the surface (track identity colour).
    let accent: Color
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

    // Renders inside the editor's `StudioTabWell` (unified tab grammar,
    // Variant D), which owns the outline + content inset.
    var body: some View {
        modifierWell

        if let modifierPickerStep {
            TrackSourceContainedModifierPicker(
                step: modifierPickerStep,
                compatibleModifiers: compatibleGenerators,
                accent: accent,
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
                accent: accent,
                layout: .modifierContained,
                onUpdate: onUpdateGeneratorParams
            )
        }
    }

    private var modifierWell: some View {
        TrackSourceModifierWell(
            trackType: trackType,
            selectedGenerator: selectedGenerator,
            isBypassed: isBypassed,
            accent: accent,
            onShowGeneratorPicker: onShowGeneratorPicker,
            onToggleBypassed: onToggleBypassed,
            onRemoveModifier: onRemoveModifier
        )
    }
}
