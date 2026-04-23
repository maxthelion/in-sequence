import SwiftUI

struct VoicePickerView: View {
    let title: String
    let choices: [AudioInstrumentChoice]
    let recentVoices: [RecentVoice]
    @Binding var selectedInstrument: AudioInstrumentChoice
    var onRecallRecent: (RecentVoice) -> Void = { _ in }
    var onSaveCurrent: () -> Void = {}

    private var sanitizedChoices: [AudioInstrumentChoice] {
        AudioInstrumentChoice.deduplicated(choices)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .studioText(.eyebrow)
                .tracking(0.9)
                .foregroundStyle(StudioTheme.mutedText)

            if !recentVoices.isEmpty {
                Menu {
                    ForEach(recentVoices) { voice in
                        Button(voice.name) {
                            onRecallRecent(voice)
                        }
                    }
                } label: {
                    Label("Recall Recent Voice", systemImage: "clock.arrow.circlepath")
                        .studioText(.bodyEmphasis)
                }
            }

            Picker("Instrument", selection: $selectedInstrument) {
                ForEach(sanitizedChoices, id: \.id) { instrument in
                    Text(instrument.displayName).tag(instrument)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Text(selectedInstrument.displayName)
                    .studioText(.body)
                    .foregroundStyle(StudioTheme.text)

                Spacer()

                Button("Save Voice Snapshot") {
                    onSaveCurrent()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}
