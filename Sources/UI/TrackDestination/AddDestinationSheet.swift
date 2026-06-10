import SwiftUI

struct AddDestinationSheet: View {
    let trackHasGroup: Bool
    let audioInstrumentChoices: [AudioInstrumentChoice]
    let sampleLibrary: AudioSampleLibrary
    let onCommit: (Destination) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectionMode: SelectionMode = .choices

    private var sanitizedAudioInstrumentChoices: [AudioInstrumentChoice] {
        AudioInstrumentChoice.deduplicated(audioInstrumentChoices)
    }

    var body: some View {
        StudioModal(
            title: selectionMode == .choices ? "Add Destination" : "Choose AU Instrument",
            subtitle: selectionMode == .choices
                ? "Pick one output path for this track."
                : "Select the Audio Unit to host for this track.",
            minWidth: 440,
            onClose: { dismiss() }
        ) {
            if selectionMode == .choices {
                VStack(alignment: .leading, spacing: 10) {
                    optionButton(
                        title: "Virtual MIDI Out",
                        detail: "Send note data to SequencerAI Out on channel 1."
                    ) {
                        commit(.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0))
                    }

                    optionButton(
                        title: "AU Instrument",
                        detail: "Host an Audio Unit instrument inside the app."
                    ) {
                        selectionMode = .audioUnit
                    }

                    optionButton(
                        title: "Sampler",
                        detail: "Use the sample engine with a library sample."
                    ) {
                        commit(defaultSampleDestination)
                    }

                    optionButton(
                        title: "Slicer",
                        detail: "Slice a sample and trigger its regions from the sequencer."
                    ) {
                        commit(.slicer(sliceSetID: SliceSet.emptyID, settings: .default))
                    }

                    if trackHasGroup {
                        optionButton(
                            title: "Inherit Group",
                            detail: "Follow the shared destination owned by this track's group."
                        ) {
                            commit(.inheritGroup)
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(sanitizedAudioInstrumentChoices, id: \.id) { choice in
                            optionButton(
                                title: choice.displayName,
                                detail: "Host this Audio Unit inside the app."
                            ) {
                                commit(.auInstrument(componentID: choice.audioComponentID, stateBlob: nil))
                            }
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
    }

    private var defaultSampleDestination: Destination {
        if let firstSample = sampleLibrary.samples.first {
            return .sample(sampleID: firstSample.id, settings: .default)
        }
        return .internalSampler(bankID: .drumKitDefault, preset: "empty")
    }

    private func commit(_ destination: Destination) {
        onCommit(destination)
        dismiss()
    }

    private func optionButton(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)

                Text(detail)
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(StudioOpacity.subtleFill), in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.subPanel, style: .continuous)
                    .stroke(StudioTheme.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private enum SelectionMode {
        case choices
        case audioUnit
    }
}
