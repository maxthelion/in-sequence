import SwiftUI

struct AddDestinationSheet: View {
    let trackHasGroup: Bool
    let audioInstrumentChoices: [AudioInstrumentChoice]
    let sampleLibrary: AudioSampleLibrary
    let onCommit: (Destination) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(EngineController.self) private var engineController
    @State private var selectionMode: SelectionMode = .choices

    private var sanitizedAudioInstrumentChoices: [AudioInstrumentChoice] {
        let live = engineController.availableAudioInstruments
        return AudioInstrumentChoice.deduplicated(live.isEmpty ? audioInstrumentChoices : live)
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
                        StudioPluginRescanHeader()

                        // The modal subtitle already says these are Audio Units
                        // to host; rows carry only their own name.
                        ForEach(sanitizedAudioInstrumentChoices, id: \.id) { choice in
                            StudioOptionButton(title: choice.displayName, accent: nil) {
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
        // Neutral pick-list cards: no choice is "current" until committed.
        StudioOptionButton(title: title, detail: detail, accent: nil, action: action)
    }

    private enum SelectionMode {
        case choices
        case audioUnit
    }
}
