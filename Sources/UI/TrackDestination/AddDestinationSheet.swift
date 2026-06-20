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
                        rescanHeader

                        // The modal subtitle already says these are Audio Units
                        // to host; rows carry only their own name.
                        ForEach(sanitizedAudioInstrumentChoices, id: \.id) { choice in
                            StudioOptionButton(title: choice.displayName) {
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
        StudioOptionButton(title: title, detail: detail, action: action)
    }

    private var rescanHeader: some View {
        HStack(spacing: 10) {
            Text(engineController.audioPluginChoiceScanState.displayText)
                .studioText(.label)
                .foregroundStyle(StudioTheme.mutedText)
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                engineController.rescanAudioPluginChoices()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .studioText(.labelBold)
            }
            .buttonStyle(.plain)
            .foregroundStyle(StudioTheme.violet)
            .disabled(engineController.audioPluginChoiceScanState.isScanning)
            .opacity(engineController.audioPluginChoiceScanState.isScanning ? 0.5 : 1)
        }
    }

    private enum SelectionMode {
        case choices
        case audioUnit
    }
}
