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
        TrackSourceSelectedWellBody(accent: bodyAccent, isEmpty: bodyIsEmpty) {
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
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, 12)
            }

            if modifierPickerStep == nil, let selectedGenerator {
                GeneratorParamsEditorView(
                    generator: selectedGenerator,
                    inputClipChoices: generatedSourceInputClips,
                    harmonicSidechainClipChoices: harmonicSidechainClips,
                    sourceMode: sourceMode,
                    accent: StudioTheme.violet,
                    layout: .modifierContained,
                    onUpdate: onUpdateGeneratorParams
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .padding(.top, 12)
            }
        }
    }

    private var displayState: TrackSourceModifierDisplayState {
        TrackSourceModifierDisplayState.resolve(
            trackType: trackType,
            selectedGenerator: selectedGenerator,
            isBypassed: isBypassed
        )
    }

    private var bodyAccent: Color {
        switch displayState {
        case .occupied:
            return StudioTheme.violet
        case .bypassed:
            return StudioTheme.amber
        case .empty:
            return StudioTheme.violet
        case .unavailable:
            return StudioTheme.border
        }
    }

    private var bodyIsEmpty: Bool {
        switch displayState {
        case .empty, .unavailable:
            return true
        case .occupied, .bypassed:
            return false
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
