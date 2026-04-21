import SwiftUI

struct AddDestinationSheet: View {
    let trackHasGroup: Bool
    let audioInstrumentChoices: [AudioInstrumentChoice]
    let sampleLibrary: AudioSampleLibrary
    let onCommit: (Destination) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectionMode: SelectionMode = .choices
    @State private var selectedAudioInstrument: AudioInstrumentChoice = .builtInSynth

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectionMode == .choices ? "Add Destination" : "Choose AU Instrument")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(StudioTheme.text)

                    Text(selectionMode == .choices
                         ? "Pick one output path for this track."
                         : "Select the Audio Unit to host for this track.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(StudioTheme.mutedText)
                }

                Spacer()

                if selectionMode == .audioUnit {
                    Button("Back") {
                        selectionMode = .choices
                    }
                    .buttonStyle(.bordered)
                }

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }

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
                        selectedAudioInstrument = audioInstrumentChoices.first ?? .builtInSynth
                        selectionMode = .audioUnit
                    }

                    optionButton(
                        title: "Sampler",
                        detail: "Use the sample engine with a library sample."
                    ) {
                        commit(defaultSampleDestination)
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
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Instrument", selection: $selectedAudioInstrument) {
                        ForEach(audioInstrumentChoices, id: \.self) { choice in
                            Text(choice.displayName).tag(choice)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    HStack {
                        Text(selectedAudioInstrument.displayName)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(StudioTheme.mutedText)
                        Spacer()
                        Button("Use Instrument") {
                            commit(.auInstrument(componentID: selectedAudioInstrument.audioComponentID, stateBlob: nil))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(StudioTheme.success)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(StudioTheme.border, lineWidth: 1)
                )
            }
        }
        .padding(24)
        .frame(minWidth: 440)
        .background(StudioTheme.stageFill)
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
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(StudioTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
